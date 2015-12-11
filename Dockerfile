FROM nixos/nix

WORKDIR /snabb
ADD . /snabb

RUN rm -rf .git
RUN nix-build -A driver tests.nix -I .

ENTRYPOINT mount -t hugetlbfs none /hugetlbfs \
  && nix-build tests.nix
