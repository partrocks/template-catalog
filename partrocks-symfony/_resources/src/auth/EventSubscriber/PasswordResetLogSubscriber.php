<?php

declare(strict_types=1);

namespace App\EventSubscriber;

use Happycode\TenZeroAuth\Event\PasswordResetRequestedEvent;
use Psr\Log\LoggerInterface;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

final class PasswordResetLogSubscriber implements EventSubscriberInterface
{
    public function __construct(private readonly LoggerInterface $logger)
    {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            PasswordResetRequestedEvent::class => 'onPasswordResetRequested',
        ];
    }

    public function onPasswordResetRequested(PasswordResetRequestedEvent $event): void
    {
        $resetUrl = $event->getResetUrl();
        $this->logger->info('Password reset requested.', [
            'reset_url' => $resetUrl,
        ]);
    }
}
