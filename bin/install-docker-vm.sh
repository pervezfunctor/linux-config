#!/bin/bash
set -e

USERNAME="${1:-dockeruser}"
PASSWORD="${2:-$USERNAME}"

if ! command -v docker > /dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl openssh-server

  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm -f get-docker.sh

  docker version
  docker run --rm hello-world

  addgroup root docker || true
fi

systemctl enable --now docker
systemctl enable --now ssh


echo 'net.ipv4.ip_forward=1' >>/etc/sysctl.d/99-ipforward.conf
sysctl -p /etc/sysctl.d/99-ipforward.conf || true


if ! id "$USERNAME" >/dev/null 2>&1; then
	useradd -m -s /bin/bash "$USERNAME"
	echo "$USERNAME:$PASSWORD" | chpasswd
fi

echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/"$USERNAME"
addgroup "$USERNAME" docker 2>/dev/null || true
