# Maintainer: Vilez0 <aur at medip dotdev>

_pkgbase=hp-wmi-patched
pkgname=${_pkgbase}-dkms
pkgver=$(grep -oP 'PACKAGE_VERSION="\K[^"]+' dkms.conf)
pkgrel=0
pkgdesc="Adds manual fan speed and performance profile control to HP laptops on Linux (patched hp-wmi)"
url="https://github.com/yunusemreyl/hp-wmi-extended"
license=("GPL")
arch=('x86_64')
depends=('glibc' 'dkms')
makedepends=()
conflicts=("${_pkgbase}")
provides=("${_pkgbase}")
source=('dkms.conf' 'hp-wmi.c' 'Makefile')
sha256sums=('SKIP' 'SKIP' 'SKIP')

package() {
	install -Dm644 'dkms.conf' "${pkgdir}/usr/src/${_pkgbase}-${pkgver}/dkms.conf"
	install -Dm644 'hp-wmi.c' "${pkgdir}/usr/src/${_pkgbase}-${pkgver}/hp-wmi.c"
	install -Dm644 'Makefile' "${pkgdir}/usr/src/${_pkgbase}-${pkgver}/Makefile"
}
