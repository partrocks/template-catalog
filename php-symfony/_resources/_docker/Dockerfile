# Local dev: stock FrankenPHP Alpine omits pdo_pgsql; Doctrine needs it for PostgreSQL.
FROM dunglas/frankenphp:1-php8.4-alpine

RUN apk add --no-cache libpq-dev $PHPIZE_DEPS \
    && docker-php-ext-install -j$(nproc) pdo_pgsql \
    && apk del $PHPIZE_DEPS libpq-dev \
    && apk add --no-cache libpq
