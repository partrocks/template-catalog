<?php

declare(strict_types=1);

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Kernel;
use Symfony\Component\Routing\Attribute\Route;

class DefaultController extends AbstractController
{
    #[Route('/', name: 'app_home')]
    public function index(#[Autowire('%kernel.environment%')] string $appEnv): Response
    {
        return $this->render('home/index.html.twig', [
            'symfonyVersion' => Kernel::VERSION,
            'phpVersion' => PHP_VERSION,
            'appEnv' => $appEnv,
        ]);
    }
}
