# HP WMI Driver (hp-wmi.c) Detailed Technical Documentation

This document contains a detailed analysis and technical reference for the `hp-wmi.c` kernel driver, which manages hardware control, thermal management, fan control, and special keyboard hotkeys for HP laptops (specifically **OMEN** and **Victus** series) in the Linux kernel.

---

## 1. Introduction and Driver Architecture

`hp-wmi.c` is a kernel driver that exposes the **WMI (Windows Management Instrumentation)** interface found on HP devices to the Linux platform. The driver utilizes two main WMI GUIDs (Globally Unique Identifiers) to control hardware features and intercept ACPI events:

| GUID Macro | GUID String Value | Function / Purpose |
| :--- | :--- | :--- |
| `HPWMI_EVENT_GUID` | `"95F24279-4D7B-4334-9387-ACCDC67EF61C"` | Reports events such as keyboard hotkeys, lid switches, and charger connection events. |
| `HPWMI_BIOS_GUID` | `"5FB7F034-2C63-45E9-BE91-3D44E2C707E4"` | Reading/writing fan speeds, temperatures, graphics card modes, and thermal profiles. |

The driver communicates with the BIOS and **Embedded Controller (EC)** by calling the `hp_wmi_perform_query` function to read hardware states (`HPWMI_READ`) or write new settings (`HPWMI_WRITE` / `HPWMI_GM`).

---

## 2. Embedded Controller (EC) Offsets

Specific registers (offsets) in the device's Embedded Controller (EC) are accessed to read and write thermal profiles. These offsets are defined under `enum hp_ec_offsets`.

### EC Offsets and Descriptions

| EC Offset Name | Hex Address | Description and Purpose |
| :--- | :---: | :--- |
| `HP_EC_OFFSET_UNKNOWN` | `0x00` | **Unknown EC Layout:** DMI-based thermal profile reading is disabled on boards with this offset. Balanced mode is selected by default on cold boot. |
| `HP_NO_THERMAL_PROFILE_OFFSET` | `0x01` | **No Thermal Profile:** Bypasses EC thermal profile reads entirely. Used on specific newer models with broken ACPI tables to prevent queries from aborting. |
| `HP_VICTUS_S_EC_THERMAL_PROFILE_OFFSET` | `0x59` | **Victus S-Series Thermal Profile Address:** Main EC memory cell storing the thermal profile status in modern Victus 16 (r and s series) and some Omen V1 motherboards. |
| `HP_OMEN_EC_THERMAL_PROFILE_FLAGS_OFFSET` | `0x62` | **Omen Thermal Profile Flags Address:** Special flag cell used on Omen devices to enable Turbo mode (`0x04`) or disable the EC timer (`0x02`). |
| `HP_OMEN_EC_THERMAL_PROFILE_TIMER_OFFSET` | `0x63` | **Omen Thermal Profile Timer Address:** The EC timer cell managed by the Omen Gaming Hub; when it reaches zero, the EC resets the profile to "Balanced". |
| `HP_OMEN_EC_THERMAL_PROFILE_OFFSET` | `0x95` | **Classic Omen Thermal Profile Address:** The profile state register used in legacy Omen (V1 Legacy) and some older Victus models. |

---

## 3. Motherboards (DMI Boards) and Offset Mappings

The driver reads the system's motherboard identifier (**DMI Board Name**) to determine which EC offsets and thermal parameters to apply.

### 3.1. Victus & Omen Motherboard Parameter Mapping Table

The motherboards defined in the `victus_s_thermal_profile_boards` array, along with their assigned thermal parameters and EC offsets, are listed below:

| Board ID (DMI Board Name) | Associated Laptop Model / Series | Thermal Parameters Struct | EC Profile Offset | Performance Value | Balanced Value | Low Power Value | Description / Special Cases |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **8A13** | OMEN by HP Laptop 16-b1xxx | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Motherboard using the classic Omen V1 layout. |
| **8A4D** | HP Omen Series | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Classic Omen V1 layout. |
| **8BAB** | HP Omen Series | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Omen motherboard using the modern 0x59 offset. |
| **8BBE** | HP Victus Series | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unknown EC layout (0x00). Software platform profile caching is used. |
| **8BCA** | HP Omen Series | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 offset. |
| **8BCD** | HP Omen Series | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 offset. |
| **8BD4** | HP Victus Series | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unknown EC layout (0x00). |
| **8BD5** | HP Victus Series | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unknown EC layout (0x00). |
| **8C76** | HP Omen Series | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 offset. |
| **8C77** | HP Omen Series | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Modern Omen using the classic 0x95 offset. |
| **8C78** | HP Omen Series | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 offset. |
| **8E35** | HP Omen Series | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 offset. |
| **8C99** | HP Victus Series | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unknown EC layout (0x00). |
| **8C9C** | HP Victus Series (e.g., 16-s1034nf) | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unknown EC layout (0x00). Requires PL1/PL2 refresh on power source switch. |
| **8D41** | HP Omen Max (e.g., 16-u0xxx) | `omen_v1_unknown_ec_thermal_params`| `0x00` | `0x31` | `0x30` | `0x30` | Omen V1 layout but with unknown EC offset. |
| **8D87** | HP Omen Series | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | Motherboard with EC reads disabled. |
| **8BA9** | HP Omen Series | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Classic Omen V1 layout. |
| **8BAC** | HP Omen 16-wf0xxx | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | **Critical ACPI Bug:** The ACPI tables have a broken GETB helper (zero-length field creation error) that aborts WMI queries. EC reads are bypassed to prevent lockups. |
| **8BC2** | Victus by HP Gaming Laptop 16-r0xxx| `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Unknown EC layout (0x00). |

---

### 3.2. Other Specialized DMI Board Groups

#### Omen Thermal Profile Capable Boards (`omen_thermal_profile_boards`)
These board names are compiled from the Omen Command Center capabilities list and use Omen-specific thermal profile paths:
> `84DA`, `84DB`, `84DC`, `8572`, `8573`, `8574`, `8575`, `8600`, `8601`, `8602`, `8603`, `8604`, `8605`, `8606`, `8607`, `860A`, `8746`, `8747`, `8748`, `8749`, `874A`, `8786`, `8787`, `8788`, `878A`, `878B`, `878C`, `87B5`, `886B`, `886C`, `88C8`, `88CB`, `88D1`, `88D2`, `88F4`, `88F5`, `88F6`, `88F7`, `88FD`, `88FE`, `88FF`, `8900`, `8901`, `8902`, `8912`, `8917`, `8918`, `8949`, `894A`, `89EB`, `8A15`, `8A42`, `8BAD`, `8BAC`, `8C77`, `8D41`, `8E35`, `8E41`, `8BA9`

#### Omen Boards Forced to Thermal Profile V0 (`omen_thermal_profile_force_v0_boards`)
These boards are forced to Omen thermal profile version 0, regardless of the system design data returned by the BIOS:
> `8607`, `8746`, `8747`, `8748`, `8749`, `874A`

#### Omen Boards with EC Timers (`omen_timed_thermal_profile_boards`)
These devices start a 120-second EC timer when performance mode is enabled. Sürücü continuously resets this timer to keep performance mode active:
> `8A15`, `8A42`, `8BAD`

#### Victus 16-d Series Boards (`victus_thermal_profile_boards`)
Models utilizing the first-generation Victus thermal profile control scheme:
> `88F8`, `8A25`

---

## 4. Thermal Profiles and Hex Mappings

The Linux `platform_profile` interface maps user profiles (Performance, Balanced, etc.) to the hex codes expected by the BIOS/EC. These codes vary across different device generations and series.

### 4.1. Classic / Standard HP Profiles
Defined in `enum hp_thermal_profile`:

| Profile Name | Hex Value | Linux Profile | Description |
| :--- | :---: | :--- | :--- |
| `HP_THERMAL_PROFILE_PERFORMANCE` | `0x00` | `performance` | Max CPU/GPU power budget and aggressive fan curves. |
| `HP_THERMAL_PROFILE_DEFAULT` | `0x01` | `balanced` | Standard everyday usage, balanced power, and noise. |
| `HP_THERMAL_PROFILE_COOL` | `0x02` | `cool` | Lower power limits to keep laptop surface temperatures low. |
| `HP_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` | Minimum fan noise via reduced power caps. |

### 4.2. HP Omen Profiles

#### Omen V0 (Older Generation)
Defined in `enum hp_thermal_profile_omen_v0`:

| Profile Name | Hex Value | Linux Profile |
| :--- | :---: | :--- |
| `HP_OMEN_V0_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_OMEN_V0_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |
| `HP_OMEN_V0_THERMAL_PROFILE_COOL` | `0x02` | `cool` |

#### Omen V1 (Modern Generation)
Defined in `enum hp_thermal_profile_omen_v1`:

| Profile Name | Hex Value | Linux Profile |
| :--- | :---: | :--- |
| `HP_OMEN_V1_THERMAL_PROFILE_DEFAULT` | `0x30` | `balanced` |
| `HP_OMEN_V1_THERMAL_PROFILE_PERFORMANCE`| `0x31` | `performance` |
| `HP_OMEN_V1_THERMAL_PROFILE_COOL` | `0x50` | `cool` |

### 4.3. HP Victus Profiles

#### Standard Victus (16-d Series)
Defined in `enum hp_thermal_profile_victus`:

| Profile Name | Hex Value | Linux Profile |
| :--- | :---: | :--- |
| `HP_VICTUS_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_VICTUS_THERMAL_PROFILE_PERFORMANCE` | `0x01` | `performance` |
| `HP_VICTUS_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` |

#### Victus S-Series (16-r and 16-s Series)
Defined in `enum hp_thermal_profile_victus_s`:

| Profile Name | Hex Value | Linux Profile |
| :--- | :---: | :--- |
| `HP_VICTUS_S_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` or `low_power` (ECO)* |
| `HP_VICTUS_S_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |

> [!NOTE]
> *On Victus S-series models, both `Balanced` and `Low Power` profiles map to `0x00` in the EC. The driver differentiates between them by querying the GPU power states (cTGP and PPAB). If both are disabled, the mode is reported as `low_power` (ECO); if PPAB is active, it is reported as `balanced`.

---

## 5. Graphics & Power Limit Controls (GPU & CPU PL1/PL2)

In modern Victus and Omen laptops, thermal profiles govern not only fan curves but also CPU and GPU power envelopes (TGP/TDP).

### 5.1. GPU Power Management (cTGP and PPAB)
The driver manages GPU power limits using `HPWMI_SET_GPU_THERMAL_MODES_QUERY` (`0x22`). The `struct victus_gpu_power_modes` controls the following parameters:

| Parameter | Type | Function / Behavior |
| :--- | :--- | :--- |
| `ctgp_enable` | `u8` | **Configurable TGP:** Unleashes the graphics card's maximum power ceiling (e.g., 120W instead of 80W). Set to `0x01` (enabled) in `Performance` mode, and `0x00` otherwise. |
| `ppab_enable` | `u8` | **Dynamic Boost (PPAB):** Balances dynamic power sharing between CPU and GPU based on workload. Set to `0x00` (disabled) in `Low Power` mode, and `0x01` in `Balanced` and `Performance` modes. |
| `dstate` | `u8` | **GPU Power Priority:** Defines power routing priority (Default is `1` representing 100% priority). |
| `gpu_slowdown_temp` | `u8` | **GPU Slowdown Temperature:** Thermal throttling limit read from the BIOS and preserved during writes. |

### 5.2. CPU Power Limits (PL1 and PL2)
On Victus S-series boards, the CPU's **PL1 (Long-term Power Limit)** and **PL2 (Short-term Power Limit)** are managed via `HPWMI_SET_POWER_LIMITS_QUERY` (`0x29`):
* `pl2` must always be greater than or equal to `pl1` (`pl2 >= pl1`).
* During power source transitions (plugging/unplugging the AC adapter), a notifier (`victus_s_powersource_event`) automatically reapplies default power limits (`HP_POWER_LIMIT_DEFAULT` -> `0x00`) to prevent performance lockups on battery power.

---

## 6. Advanced Fan Control (Hwmon Framework)

The driver interfaces with the Linux hardware monitoring subsystem (`hwmon`) to expose fan speed readings and enable manual override capabilities.

### 6.1. Fan Control Modes
Manual and automatic fan control is defined under `enum pwm_modes`:

| Mode Name | Value | Description |
| :--- | :---: | :--- |
| `PWM_MODE_MAX` | `0` | **Maximum Fan:** Forces fans to run at 100% duty cycle. |
| `PWM_MODE_MANUAL` | `1` | **Manual Override:** Allows users to set target fan RPMs directly via sysfs. |
| `PWM_MODE_AUTO` | `2` | **Automatic EC Control:** Relinquishes control to the Embedded Controller's internal thermal algorithms. |

### 6.2. Keep-Alive Watchdog Timer
The HP Embedded Controller (EC) starts a **120-second safety timer** when entering manual fan mode or maximum fan mode. If no WMI commands are received within 120 seconds, the EC reverts to automatic mode (`AUTO`) for safety.

To prevent this, the driver runs a background watchdog thread (**Delayed Work - Keep Alive Watchdog**):
* Sürücü issues a keep-alive refresh every **90 seconds** (`KEEP_ALIVE_DELAY_SECS = 90`), writing the active mode and speeds back to the EC.
* This constantly resets the EC's 120-second safety timer, keeping manual control active.
* When the user switches back to `AUTO`, the watchdog thread is cancelled (`cancel_delayed_work_sync`) and the EC takes over.

### 6.3. Victus S Fan Table Structure
On Victus S-series laptops, fan speed boundaries are extracted from the BIOS via `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY` (`0x2F`):

```c
struct victus_s_fan_table_header {
    u8 unknown;
    u8 num_entries; // Number of step entries in the fan curve
} __packed;

struct victus_s_fan_table_entry {
    u8 cpu_rpm;     // CPU fan speed (value * 100 RPM)
    u8 gpu_rpm;     // GPU fan speed (value * 100 RPM)
    u8 unknown;
} __packed;
```
* **Minimum Boundaries:** Extracted from the first step in the table (`entries[0].cpu_rpm`).
* **Maximum Boundaries:** Extracted from the last step (`entries[num_entries-1]`).
* **Graceful Degradation:** If the fan table query is unsupported or malformed, the driver automatically registers a safe **5000 RPM fallback table** (`setup_fallback_fan_limits`) instead of failing probe.

---

## 7. WMI Event Notifications (Event IDs)

ACPI notifications received via `HPWMI_EVENT_GUID` and the driver's response:

| Event ID (Hex) | Event Name | Trigger Condition & Driver Behavior |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DOCK_EVENT` | Docking/undocking or tablet mode transition. Reported via `input_report_switch`. |
| `0x02` | `HPWMI_PARK_HDD` | Free-fall sensor alert; parks the HDD read/write head for data protection. |
| `0x03` | `HPWMI_SMART_ADAPTER` | Non-genuine or underpowered charger warning. |
| `0x04` | `HPWMI_BEZEL_BUTTON` | Special bezel hotkey presses; reported as a key event. |
| `0x05` | `HPWMI_WIRELESS` | Wireless state toggles (Wi-Fi, Bluetooth, WWAN); updates rfkill states. |
| `0x06` | `HPWMI_CPU_BATTERY_THROTTLE` | CPU power limits reduced due to 3-cell battery safety envelope. |
| `0x0A` | `HPWMI_COOLSENSE_SYSTEM_MOBILE` | HP CoolSense: Laptop is on a lap, surface temps are lowered. |
| `0x0B` | `HPWMI_COOLSENSE_SYSTEM_HOT` | HP CoolSense: Laptop is on a desk, full performance allowed. |
| `0x0D` | `HPWMI_BACKLIT_KB_BRIGHTNESS` | Backlit keyboard brightness levels updated. |
| `0x1A` | `HPWMI_CAMERA_TOGGLE` | **Camera Shutter State:** Physical lens cover state changed (`0xFF`: Shut, `0xFE`: Open). Reports standard `SW_CAMERA_LENS_COVER`. |
| `0x1B` | `HPWMI_FN_P_HOTKEY` | **Fn + P Combination:** Cycles through platform profile options (`platform_profile_cycle`). |
| `0x1D` | `HPWMI_OMEN_KEY` | **Omen Key:** Launches Omen Gaming Hub; reported as `KEY_PROG2`. |

---

## 8. Driver WMI Command & Query References

Below is a reference of WMI command and query types used in queries (`hp_wmi_perform_query`):

### 8.1. WMI Query Types (`enum hp_wmi_commandtype`)
Passed as the first argument (`query`) to `hp_wmi_perform_query`:

| Hex Code | Query Name (Macro) | Purpose |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DISPLAY_QUERY` | Retrieve display status. |
| `0x02` | `HPWMI_HDDTEMP_QUERY` | Query HDD temperature sensors. |
| `0x03` | `HPWMI_ALS_QUERY` | Ambient Light Sensor controls. |
| `0x04` | `HPWMI_HARDWARE_QUERY` | Tablet and dock states query. |
| `0x05` | `HPWMI_WIRELESS_QUERY` | Older generation wireless switch states. |
| `0x07` | `HPWMI_BATTERY_QUERY` | Read battery health and metrics. |
| `0x09` | `HPWMI_BIOS_QUERY` | Enable BIOS hotkey features (writes `0x6E`). |
| `0x0B` | `HPWMI_FEATURE_QUERY` | Query post-2008 BIOS feature sets. |
| `0x0C` | `HPWMI_HOTKEY_QUERY` | Read keycode of the pressed hotkey. |
| `0x0D` | `HPWMI_FEATURE2_QUERY` | Query post-2009 advanced feature sets. |
| `0x1B` | `HPWMI_WIRELESS2_QUERY` | Modern multi-device wireless state manager (rfkill2). |
| `0x2A` | `HPWMI_POSTCODEERROR_QUERY` | Read and clear BIOS POST error codes. |
| `0x40` | `HPWMI_SYSTEM_DEVICE_MODE` | Graphics mode switcher (Mux Switch) and tablet mode detection. |
| `0x4C` | `HPWMI_THERMAL_PROFILE_QUERY` | Read/write classic thermal profiles. |

### 8.2. Gaming / Omen Specific Queries (`enum hp_wmi_gm_commandtype`)
Gaming Command Center queries used to manage performance features:

| Hex Code | Query Name (Macro) | Purpose |
| :---: | :--- | :--- |
| `0x10` | `HPWMI_FAN_COUNT_GET_QUERY` | Reads fan count. Triggers the EC's "user-defined fan mode". |
| `0x11` | `HPWMI_FAN_SPEED_GET_QUERY` | Read classic fan speed. |
| `0x1A` | `HPWMI_SET_PERFORMANCE_MODE` | Write Omen thermal profiles to the EC. |
| `0x21` | `HPWMI_GET_GPU_THERMAL_MODES_QUERY`| Read GPU cTGP and PPAB states. |
| `0x22` | `HPWMI_SET_GPU_THERMAL_MODES_QUERY`| Write GPU cTGP and PPAB limits. |
| `0x26` | `HPWMI_FAN_SPEED_MAX_GET_QUERY` | Query whether max fan mode is active. |
| `0x27` | `HPWMI_FAN_SPEED_MAX_SET_QUERY` | Toggle max fan mode (`0x01` to enable, `0x00` to disable). |
| `0x28` | `HPWMI_GET_SYSTEM_DESIGN_DATA` | Fetch system design version (Omen V0 or V1). |
| `0x29` | `HPWMI_SET_POWER_LIMITS_QUERY` | Configure CPU PL1 and PL2 thresholds. |
| `0x2D` | `HPWMI_VICTUS_S_FAN_SPEED_GET_QUERY`| Simultaneously read CPU and GPU RPMs on Victus S series. |
| `0x2E` | `HPWMI_VICTUS_S_FAN_SPEED_SET_QUERY`| Directly override fan RPMs on Victus S series. |
| `0x2F` | `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY`| Read fan stepped curve boundaries from the BIOS. |

---

## 9. Critical Bugs and Workarounds (Fixes)

Over time, several hardware compatibility workarounds have been integrated into the driver:

### 1. NVIDIA Dynamic Boost DC Power Cap Fix (xcellsior patch)
* **Problem:** On boards with uncharacterized EC layouts (e.g., HP Omen Max 16, board `8D41`), sending fan WMI control packets during module load disabled the NVIDIA Dynamic Boost DC controller, capping the GPU's power target (TGP) to its base level (e.g., 80W instead of 120W).
* **Fix:** Sürücü bypasses initial WMI fan-mode reconciliation if the EC offset is `HP_EC_OFFSET_UNKNOWN`. Fan mode sync is deferred until the first user write to sysfs `pwm_enable`, preserving maximum GPU power.

### 2. ACPI GETB Method Crash Prevention (Board 8BAC)
* **Problem:** HP Omen 16-wf0xxx (`8BAC`) motherboards contain an ACPI DSDT bug in their `GETB` helper, attempting to create a zero-length field. This caused WMI method evaluations to abort, crashing the ACPI subsystem.
* **Fix:** The board is explicitly mapped to `omen_v1_no_ec_thermal_params`. The driver skips all EC-based thermal profile reading, relying on cached configurations to maintain system stability.

### 3. Camera Lens Privacy Shutter (`camera_shutter_input_setup`)
* **Problem:** Models with physical privacy switches required integration with the user interface to warn when the camera was shuttered.
* **Solution:** Sürücü registers a virtual input device `HP WMI camera shutter`. When event `0x1A` is triggered, the lens cover state is parsed (`0xFF` for closed, `0xFE` for open) and mapped to standard Linux kernel key code `SW_CAMERA_LENS_COVER`.
