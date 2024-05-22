#!/usr/bin/env bash

# Copyright (c) Lumu Technologies. All rights reserved.

set -e

INSTALLATION_SCRIPT_VERSION="v1.1.0"
BASE_REPOSITORY_URL="https://packages.lumu.io"
LUMU_PACKAGE_NAME="lumu-linux-agent"
LUMU_REPOSITORY_NAME="lumu"
CAN_USE_WGET=true

VERBOSE=false

info() {
  echo "[INFO] $1"
}

debug() {
  if [ "$VERBOSE" = true ]; then
    echo "[DEBUG] $1"
  fi
}

warning() {
  echo "[WARNING] $1"
}

error() {
  echo "[ERROR] $1"
}

fatal() {
  echo "[FATAL] $1"
  exit 1
}

print_help_message() {
  echo "Usage: lumu-linux-agent [OPTION]..."
  echo ""
  echo "OPTIONS:"
  echo "  -l, --license LICENSE    If set, the activation process will be executed after installation success"
  echo "                           using the LICENSE as activation code."
  echo "  -i, --install            Installs the dependencies, repository and the Lumu Linux Agent."
  echo "  -u, --uninstall          Totally remove Lumu Linux Agent repositories and binaries from system"
  echo "                           using the LICENSE as activation code."
  echo "  -v, --verbose            Print more information about every step."
  echo "      --version            Print installation script version and exit."
  echo "  -h, --help               Print this help message and exit."
}

print_version_message() {
  echo "$0 $INSTALLATION_SCRIPT_VERSION"
}

check_agent_installed() {
  if [ -d "/opt/lumu" ]; then
    fatal "Lumu Linux Agent is already installed. Exiting."
  fi
}

detect_linux_distribution() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    OS=Debian
    VER=$(cat /etc/debian_version)
  else
    echo "$0 error: could not detect your linux distribution version"
    echo "Please, fallback to manual installation process <https://docs.lumu.io/portal/en/kb/articles/lumu-agent-for-linux>"
    exit 1
  fi
}

has_wget_installed() {
  if ! [ -x "$(command -v wget)" ]; then
    CAN_USE_WGET=false
  fi
}

rpm_based_install() {
  RPM_BASED_NAME=$1

  info "Installing Lumu repository public key."
  rpm --import "$BASE_REPOSITORY_URL/$RPM_BASED_NAME/$RPM_BASED_NAME.pub.key"

  info "Installing Lumu repository."
  LANG="C.UTF-8" yum-config-manager --add-repo "$BASE_REPOSITORY_URL/$RPM_BASED_NAME/lumu.repo"

  info "Installing the Lumu Linux Agent package."
  LANG="C.UTF-8" yum install -q -y "$LUMU_PACKAGE_NAME" >/dev/null 2>&1
}

suse_based_install() {
  info "Installing Lumu repository."
  zypper --gpg-auto-import-keys -q addrepo "$BASE_REPOSITORY_URL/sles/lumu.repo"
  info "Installing the Lumu Linux Agent package."
  zypper --gpg-auto-import-keys -q install -y "$LUMU_PACKAGE_NAME"
}

apt_based_install() {
  APT_BASED_NAME=$1
  TMP_LUMU_DIR="/tmp/lumu"

  mkdir -p "$TMP_LUMU_DIR"
  install -m 0755 -d /etc/apt/keyrings
  info "Fetching repository public key."

  if [ "$CAN_USE_WGET" = true ]; then
    if ! wget -q -O "$TMP_LUMU_DIR/lumu.pub.key" "$BASE_REPOSITORY_URL/$APT_BASED_NAME/$APT_BASED_NAME.pub.key"; then
      warning "Could not fetch repository public key using wget. Trying again with curl..."
      CAN_USE_WGET=false
      apt_based_install "$APT_BASED_NAME"
    fi
  else
    if ! curl -fsSL "$BASE_REPOSITORY_URL/$APT_BASED_NAME/$APT_BASED_NAME.pub.key" -o "$TMP_LUMU_DIR/lumu.pub.key"; then
      fatal "Could not fetch repository public key using curl. Please contact our support team."
    fi
  fi

  gpg --batch --yes --dearmor -o /etc/apt/keyrings/lumu.gpg "$TMP_LUMU_DIR/lumu.pub.key"
  chmod a+r /etc/apt/keyrings/lumu.gpg

  ARCH="$(dpkg --print-architecture)"
  CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

  if [ "$APT_BASED_NAME" = "ubuntu" ]; then
    echo \
      "deb [arch=$ARCH signed-by=/etc/apt/keyrings/lumu.gpg] $(. /etc/os-release && echo "$BASE_REPOSITORY_URL/$APT_BASED_NAME/$CODENAME") \
      $CODENAME stable" | tee /etc/apt/sources.list.d/lumu.list >/dev/null
  else
    echo \
      "deb [arch=$ARCH signed-by=/etc/apt/keyrings/lumu.gpg] $(. /etc/os-release && echo "$BASE_REPOSITORY_URL/$APT_BASED_NAME") \
      $CODENAME stable" | tee /etc/apt/sources.list.d/lumu.list >/dev/null
  fi

  info "Updating packages index."
  apt update >/dev/null 2>&1

  info "Installing package."
  apt -qq install -y "$LUMU_PACKAGE_NAME" >/dev/null 2>&1
}

apt_based_uninstall() {
  info "Removing the $LUMU_PACKAGE_NAME package."
  apt -qq remove -y --purge "$LUMU_PACKAGE_NAME" >/dev/null 2>&1 || true
  info "Removing Lumu repository."
  rm -f /etc/apt/sources.list.d/"$LUMU_REPOSITORY_NAME".list || warning "Could not remove Lumu repository. It's installed ?"
  info "Removing Lumu public GPG key."
  rm -f /etc/apt/keyrings/lumu.gpg
  info "Updating system repository index."
  apt update >/dev/null 2>&1 || warning "Could not update packages index. It's your apt config okay?"
}

rpm_based_uninstall() {
  info "Removing the $LUMU_PACKAGE_NAME package."
  yum remove -y -q "$LUMU_PACKAGE_NAME" >/dev/null 2>&1
  info "Removing Lumu repository."
  rm -f /etc/yum.repos.d/"$LUMU_REPOSITORY_NAME".repo || warning "Could not remove Lumu repository. It's installed ?"
}

suse_based_uninstall() {
  info "Removing the $LUMU_PACKAGE_NAME package."
  zypper rm -y --clean-deps "$LUMU_PACKAGE_NAME" >/dev/null 2>&1 || true
  info "Removing Lumu repository."
  rm -f /etc/zypp/repos.d/lumu-agent-stable.repo || warning "Could not remove Lumu repository. It's installed ?"
}

apt_based_install_dependencies() {
  info "Updating repository index."
  apt -qq update >/dev/null 2>&1 || fatal "Could not update repositories. Please, run \`sudo apt update\` for more information."
  info "Installing dependencies."
  apt -qq install -y ca-certificates wget curl gnupg >/dev/null 2>&1 || fatal "Could not install dependencies. Exiting."
}

rpm_based_install_dependencies() {
  info "Installing dependencies."
  yum install -q -y wget curl yum-utils >/dev/null 2>&1 || fatal "Could not install dependencies. Exiting."
}

suse_based_install_dependencies() {
  info "Installing dependencies."
  zypper install -y wget curl >/dev/null 2>&1 || fatal "Could not install dependencies. Exiting."
}

### Main ###

while [[ $# -gt 0 ]]; do
  case $1 in
  -v | --verbose)
    VERBOSE=true
    shift
    ;;
  --version)
    print_version_message
    exit 0
    ;;
  -h | --help)
    print_help_message
    exit 0
    ;;
  -l | --license)
    AGENT_ACTIVATION_CODE="$2"
    shift
    shift
    ;;
  -i | --install)
    OPERATION="install"
    shift
    ;;
  -u | --uninstall)
    OPERATION="uninstall"
    shift
    ;;
  -* | --*)
    error "Unknown option \"$1\""
    print_help_message
    exit 1
    ;;
  *)
    # Note: Parse positional arguments
    shift
    ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
  error "This application must run as root."
  exit 1
fi

detect_linux_distribution

if [ "$OPERATION" = "uninstall" ]; then
  info "Uninstalling the Lumu Linux Agent"

  case $OS in
  "Ubuntu" | "Debian GNU/Linux" | "KDE neon")
    apt_based_uninstall
    ;;
  "Fedora Linux" | "Red Hat Enterprise Linux")
    rpm_based_uninstall
    ;;
  "SLES" | "openSUSE Leap")
    suse_based_uninstall
    ;;
  *)
    error "Platform $OS $VER is not supported by the Lumu Linux Agent installer."
    error "Please, fallback to manual installation process at <https://docs.lumu.io/portal/en/kb/articles/lumu-agent-for-linux>"
    exit 1
    ;;
  esac

  info "Done."
elif [ "$OPERATION" = "install" ]; then
  check_agent_installed
  has_wget_installed

  info "Installing Lumu Linux Agent for $OS $VER..."

  case $OS in
  "Ubuntu" | "KDE neon")
    apt_based_install_dependencies
    apt_based_install "ubuntu"
    ;;
  "Debian GNU/Linux")
    apt_based_install_dependencies
    apt_based_install "debian"
    ;;
  "Fedora Linux")
    rpm_based_install_dependencies
    rpm_based_install "fedora"
    ;;
  "SLES" | "openSUSE Leap")
    suse_based_install_dependencies
    suse_based_install
    ;;
  "Red Hat Enterprise Linux")
    rpm_based_install_dependencies
    rpm_based_install "rhel"
    ;;
  *)
    error "Platform $OS $VER is not supported by the Lumu Linux Agent installer."
    error "Please, fallback to manual installation process at <https://docs.lumu.io/portal/en/kb/articles/lumu-agent-for-linux>"
    exit 1
    ;;
  esac

  if [ -n "$AGENT_ACTIVATION_CODE" ]; then
    info "Activating agent..."
    /opt/lumu/lumu-agent-support --activate "$AGENT_ACTIVATION_CODE"
  fi

  info "Done!"
else
  print_help_message
  exit 0
fi
