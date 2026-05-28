# 🌀 HP-WMI-Extended

<p align="center">
  <strong>An advanced, patched Linux kernel module for HP Omen, Victus, and companion laptops, unlocking full manual fan speed controls and seamless platform performance profile integration.</strong>
</p>

<p align="center">
  <a href="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html">
    <img src="https://img.shields.io/badge/License-GPL%20v2-blue.svg?style=for-the-badge" alt="License: GPL v2">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/Kernel-5.x%20%7C%206.x%20%7C%207.x-success.svg?style=for-the-badge" alt="Kernel Compatibility">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/Platform-Linux-orange.svg?style=for-the-badge" alt="Platform: Linux">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/DKMS-Automated-brightgreen.svg?style=for-the-badge" alt="DKMS Supported">
  </a>
</p>

---

## ⚡ Introduction

The default Linux kernel `hp-wmi` driver leaves a lot of performance on the table. This **extended** variant is fully patched to expose deep hardware registers inside the ACPI Embedded Controller (EC) of your HP laptop. 

It provides real-time cooling override capabilities, enabling you to switch thermal profiles, use custom RPM fan targets, and keep your laptop running exceptionally cool during heavy gaming or compilation workloads.

> [!NOTE]
> *Based on the upstream and TUXOV's [hp-wmi driver](https://github.com/TUXOV/hp-wmi-fan-and-backlight-control). All credit for deciphering the ACPI WMI communication commands belongs to the upstream project.*

---

## ✨ Core Features

*   🌀 **Manual Fan Speed Control** — Bypass BIOS locks to assign precise RPM targets.
*   🔄 **Dynamic Mode Switching** — Toggle between **Auto**, **Manual**, and **Max** cooling profiles on the fly.
*   📊 **Platform Profiles Integration** — Fully integrated with Linux ACPI platform profiles. Changes sync instantly with `power-profiles-daemon` (GNOME/KDE system power menus).
*   ⌨️ **Physical Key Mapping** — Native listener for the **Fn+P** performance switch hotkey and the dedicated **OMEN** dashboard key.
*   🛠️ **DKMS Automated Rebuilds** — Automatically compiles and loads itself whenever you update your Linux kernel.

---

## 🔧 Installation

This driver supports all major Linux distributions, including **Arch Linux / Manjaro**, **Ubuntu / Debian**, **Fedora / RHEL**, **openSUSE**, **Void Linux**, and **Gentoo**.

### 1. Quick Install (All Distros)

The included interactive `setup.sh` automatically installs system compilation tools and kernel headers, backs up the stock `hp-wmi.ko` driver, compiles the patched module, registers it with DKMS, and loads it into the kernel:

```bash
git clone https://github.com/yunusemreyl/hp-wmi-extended
cd hp-wmi-extended
sudo ./setup.sh
```

### 2. Manual DKMS Installation

If you prefer to register the source directory with DKMS manually:

```bash
git clone https://github.com/yunusemreyl/hp-wmi-extended
cd hp-wmi-extended
make
sudo make install-dkms
```

### 3. Arch Linux (AUR)

Generate and install the package locally using `makepkg`:

```bash
git clone https://github.com/yunusemreyl/hp-wmi-extended
cd hp-wmi-extended
make install-arch
```

### 4. NixOS Integration

To integrate this driver directly into your NixOS configuration, declare this repository in your flake inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hp_wmi_extended.url = "github:yunusemreyl/hp-wmi-extended";
  };
  outputs = { self, nixpkgs, hp_wmi_extended, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        hp_wmi_extended.nixosModules.default
        {
          hardware.hp-wmi-patched = {
            enable = true;
            # victus-15-support.enable = true; # Force Victus 15 manual fan control
          };
        }
      ];
    };
  };
}
```

---

## 🎮 How to Use

### 1. Fan Controller API

The driver exposes a standard Linux `hwmon` interface. You manage cooling states by writing to `pwm1_enable`:

| Value | Mode | Behavior |
| :---: | :--- | :--- |
| **`0`** | 🔴 **Max** | Disables BIOS controls; forces all fans to run at maximum hardware RPM. |
| **`1`** | 🟡 **Manual** | Bypasses BIOS target calculations; allows custom RPM speeds via the target sysfs nodes. |
| **`2`** | 🟢 **Auto** | Re-delegates fan control back to the motherboard BIOS (standard factory state). |

```bash
# Step 1: Switch the fan controller to manual mode
echo 1 | sudo tee /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1_enable

# Step 2: Set exact cooling RPM targets (verify your fan*_max RPM first)
echo 5500 | sudo tee /sys/devices/platform/hp-wmi/hwmon/hwmon*/fan1_target
echo 5200 | sudo tee /sys/devices/platform/hp-wmi/hwmon/hwmon*/fan2_target

# Step 3: Revert back to motherboard automatic control
echo 2 | sudo tee /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1_enable
```

> [!TIP]
> Use `cat /sys/devices/platform/hp-wmi/hwmon/hwmon*/fan*_max` to find the hardware limit of your cooling fans. Writing an RPM target above this limit will safely return `-EINVAL`.

### 2. Thermal & Performance Profiles

Switch between ACPI power profiles, which coordinates power limits, CPU clock boosts, and cooling curves in unison:

```bash
# Query the active performance profile
cat /sys/firmware/acpi/platform_profile

# List available ACPI profile modes
cat /sys/firmware/acpi/platform_profile_choices

# Switch performance profiles manually
echo performance | sudo tee /sys/firmware/acpi/platform_profile
echo balanced    | sudo tee /sys/firmware/acpi/platform_profile
echo low-power   | sudo tee /sys/firmware/acpi/platform_profile
```

*Note: Pressing the physical **Fn+P** key combination on your keyboard will cycle through these profiles automatically.*

---

## ⚠️ Hardware Workarounds

> [!WARNING]
> **HP Victus 15 Models:** 
> HP has disabled manual fan speed controls on the Victus 15 BIOS at a firmware level, even though the hardware registers are present. To force manual fan support bypasses, pass the override parameter when loading:
> ```bash
> sudo insmod hp-wmi.ko force_fan_control_support=true
> ```

---

## 💻 Tested Hardware

This patched module is verified to compile, load, and run perfectly on:
-   OmenCtl [https://github.com/yunusemreyl/OmenCtl] users

---

## 🛡️ License & Disclaimer

*   **License:** Distributed under the **GPL-2.0-or-later** license. See the [LICENSE](LICENSE) file for details.
*   **Disclaimer:** **USE AT YOUR OWN RISK.** Overriding hardware cooling limits or target thermal profiles can affect system stability. The authors hold no responsibility for any hardware damages.
