FROM php:8.3-apache

WORKDIR /var/www/html

# Cloud preflight context is split into app/ and _partrocks/.
COPY app/ /var/www/html/

EXPOSE 80

CMD ["apache2-foreground"]
