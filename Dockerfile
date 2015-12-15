FROM nixos/nix

WORKDIR /snabb
ADD . /snabb

RUN nix-build -Q -A driver tests.nix -I .
RUN rm -rf .git

COPY docker-entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
