<?php

declare(strict_types=1);

namespace App\Controller;

use Happycode\TenZeroAuth\Service\TenZeroSecurityService;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

final class HomeController extends AbstractController
{
    public function __construct(private readonly TenZeroSecurityService $security)
    {
    }

    #[Route('/', name: 'app_home_public')]
    public function public(): Response
    {
        return $this->render('home/public.html.twig');
    }

    #[Route('/bye', name: 'app_home_bye')]
    public function bye(): Response
    {
        return $this->render('home/bye.html.twig');
    }

    #[Route('/private', name: 'app_home_private')]
    public function private(): Response
    {
        return $this->render('home/private.html.twig', ['user' => $this->security->getUser()]);
    }
}
