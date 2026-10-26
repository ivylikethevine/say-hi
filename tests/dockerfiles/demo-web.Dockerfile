# The README's top GIF's box (docs/tapes/demo.tape): a debian web host with
# systemd as init, so the tape's restart is a real `systemctl`, and nginx in
# front of an upstream on the wrong port, so the site answers 502 until the
# tape fixes the port. docs/tapes/fixtures.sh's up_container runs it with the
# flags systemd needs in a container and waits for nginx, and
# demo-login.Dockerfile adds the account on top.
FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv nginx vim sudo curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default \
    && printf '%s\n' 'server {' '    listen 80 default_server;' '    location / {' \
      '        proxy_pass http://127.0.0.1:8081;' '    }' '}' >/etc/nginx/sites-available/app \
    && printf '%s\n' 'server {' '    listen 127.0.0.1:8080;' '    location / {' \
      '        return 200 "hi from the app";' '    }' '}' >/etc/nginx/sites-available/backend \
    && ln -s /etc/nginx/sites-available/app /etc/nginx/sites-available/backend /etc/nginx/sites-enabled/
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
