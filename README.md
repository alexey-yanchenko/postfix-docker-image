Postfix Docker Image
====================

# Build
TODO: link to postfix fork

docker build . -t maildealer/postfix:tag

# Usage

docker run -p 255:25 -v $(pwd)/main.cf:/etc/postfix/main.cf.d/10-custom.cf maildealer/postfix:tag
