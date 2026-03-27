<?php

declare(strict_types=1);

namespace App\Controller;

use Doctrine\DBAL\Connection;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Kernel;
use Symfony\Component\Routing\Attribute\Route;

class DefaultController extends AbstractController
{
    #[Route('/', name: 'app_home')]
    public function index(
        #[Autowire('%kernel.environment%')] string $appEnv,
        Connection $connection,
    ): Response {
        $dbConnected = false;
        $dbError = null;
        try {
            $connection->executeQuery($connection->getDatabasePlatform()->getDummySelectSQL());
            $dbConnected = true;
        } catch (\Throwable $e) {
            $dbError = $appEnv === 'prod'
                ? 'Could not connect. Verify DATABASE_URL and database availability.'
                : $e->getMessage();
        }

        return $this->render('home/index.html.twig', [
            'symfonyVersion' => Kernel::VERSION,
            'phpVersion' => PHP_VERSION,
            'appEnv' => $appEnv,
            'dbConnected' => $dbConnected,
            'dbError' => $dbError,
        ]);
    }
}
