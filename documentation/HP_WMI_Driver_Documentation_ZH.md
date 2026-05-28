# HP WMI 驱动程序 (hp-wmi.c) 详细技术文档

本文件包含 Linux 内核中 `hp-wmi.c` 驱动程序的详细分析和技术参考。该驱动程序用于管理 HP 笔记本电脑（特别是 **OMEN 暗影精灵** 和 **Victus 光影精灵** 系列）的硬件控制、散热管理、风扇控制以及专用键盘快捷键。

---

## 1. 简介与驱动架构

`hp-wmi.c` 是一个内核驱动程序，它将 HP 设备上的 **WMI (Windows Management Instrumentation)** 接口暴露给 Linux 平台。驱动程序使用两个主要的 WMI GUID（全局唯一标识符）来控制硬件功能并拦截 ACPI 事件：

| GUID 宏定义 | GUID 字符串值 | 功能与用途 |
| :--- | :--- | :--- |
| `HPWMI_EVENT_GUID` | `"95F24279-4D7B-4334-9387-ACCDC67EF61C"` | 报告键盘快捷键、屏幕翻盖状态、充电器连接状态等事件。 |
| `HPWMI_BIOS_GUID` | `"5FB7F034-2C63-45E9-BE91-3D44E2C707E4"` | 读写风扇速度、温度、显卡切换模式以及散热模式。 |

驱动程序通过调用 `hp_wmi_perform_query` 函数与 BIOS 和 **嵌入式控制器 (EC - Embedded Controller)** 通信，以读取硬件状态（`HPWMI_READ`）或写入新设置（`HPWMI_WRITE` / `HPWMI_GM`）。

---

## 2. 嵌入式控制器 (EC) 偏移量

通过访问设备嵌入式控制器 (EC) 中的特定寄存器（偏移量，Offsets）来读写散热模式状态。这些偏移量在 `enum hp_ec_offsets` 中定义。

### EC 偏移量及功能定义

| EC 偏移量名称 | 十六进制地址 | 描述与用途 |
| :--- | :---: | :--- |
| `HP_EC_OFFSET_UNKNOWN` | `0x00` | **未知 EC 布局：** 在具有此偏移量的硬板上，基于 DMI 的散热模式读取将被禁用。冷启动时默认选择平衡（`BALANCED`）模式。 |
| `HP_NO_THERMAL_PROFILE_OFFSET` | `0x01` | **无散热模式：** 完全绕过 EC 散热模式读取。用于某些具有损坏 ACPI 表的新型号，以防止查询中断挂起。 |
| `HP_VICTUS_S_EC_THERMAL_PROFILE_OFFSET` | `0x59` | **Victus S 系列散热模式地址：** 现代 Victus 16（r 和 s 系列）以及部分 Omen V1 主板上存储散热状态的主要 EC 内存单元。 |
| `HP_OMEN_EC_THERMAL_PROFILE_FLAGS_OFFSET` | `0x62` | **Omen 散热模式标志地址：** Omen 设备上使用的特殊标志单元，用于启用狂暴模式/狂暴标志（`0x04`）或禁用 EC 定时器（`0x02`）。 |
| `HP_OMEN_EC_THERMAL_PROFILE_TIMER_OFFSET` | `0x63` | **Omen 散热定时器地址：** 由 Omen 游戏中心（Omen Gaming Hub）管理的 EC 定时器单元；当减至零时，EC 会自动将模式重置为“平衡”模式。 |
| `HP_OMEN_EC_THERMAL_PROFILE_OFFSET` | `0x95` | **经典 Omen 散热模式地址：** 较旧一代 Omen (V1 Legacy) 和某些早期 Victus 型号中使用的散热配置寄存器。 |

---

## 3. 主板 (DMI Board) 与偏移量映射

驱动程序读取系统的物理主板标识符（**DMI Board Name**）以确定要应用的 EC 偏移量和散热参数。

### 3.1. Victus 和 Omen 主板参数映射表

`victus_s_thermal_profile_boards` 数组中定义的主板及其分配的散热参数和 EC 偏移量如下表所示：

| 主板 ID (DMI Board Name) | 关联笔记本电脑型号/系列 | 散热参数配置结构体 | EC 模式偏移量 | 狂暴 (Performance) 值 | 平衡 (Balanced) 值 | 安静 (Low Power) 值 | 描述/特殊情况 |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **8A13** | OMEN by HP Laptop 16-b1xxx | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | 使用经典 Omen V1 布局的主板。 |
| **8A4D** | HP Omen 系列 | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | 经典 Omen V1 布局。 |
| **8BAB** | HP Omen 系列 | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | 使用现代 0x59 偏移量的 Omen 主板。 |
| **8BBE** | HP Victus 系列 | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | 未知 EC 布局 (0x00)。使用软件配置缓存和跟踪。 |
| **8BCA** | HP Omen 系列 | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | 现代 0x59 偏移量。 |
| **8BCD** | HP Omen 系列 | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | 现代 0x59 偏移量。 |
| **8BD4** | HP Victus 系列 | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | 未知 EC 布局 (0x00)。 |
| **8BD5** | HP Victus 系列 | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | 未知 EC 布局 (0x00)。 |
| **8C76** | HP Omen 系列 | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | 现代 0x59 偏移量。 |
| **8C77** | HP Omen 系列 | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | 使用经典 0x95 偏移量的现代 Omen。 |
| **8C78** | HP Omen 系列 | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | 现代 0x59 偏移量。 |
| **8E35** | HP Omen 系列 | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | 现代 0x59 偏移量。 |
| **8C99** | HP Victus 系列 | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | 未知 EC 布局 (0x00)。 |
| **8C9C** | HP Victus 系列 (如 16-s1034nf) | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | 未知 EC 布局 (0x00)。切换电源源（拔插电源）时需重置 PL1/PL2。 |
| **8D41** | HP Omen Max (如 16-u0xxx) | `omen_v1_unknown_ec_thermal_params`| `0x00` | `0x31` | `0x30` | `0x30` | Omen V1 布局，但 EC 偏移量未知。 |
| **8D87** | HP Omen 系列 | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | EC 读取已完全禁用的主板。 |
| **8BA9** | HP Omen 系列 | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | 经典 Omen V1 布局。 |
| **8BAC** | HP Omen 16-wf0xxx | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | **严重 ACPI 漏洞：** 它的 ACPI 表包含损坏的 GETB 辅助函数（零长度字段创建错误），会导致 WMI 查询终止。驱动程序完全绕过 EC 读取以防止锁死。 |
| **8BC2** | Victus by HP Gaming Laptop 16-r0xxx| `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | 未知 EC 布局 (0x00)。 |

---

### 3.2. 其他专用 DMI 主板组

#### 支持 Omen 散热模式的主板组 (`omen_thermal_profile_boards`)
这些主板型号根据 Windows 的 Omen Command Center 功能列表整理，将使用 Omen 专用的散热查询路径：
> `84DA`, `84DB`, `84DC`, `8572`, `8573`, `8574`, `8575`, `8600`, `8601`, `8602`, `8603`, `8604`, `8605`, `8606`, `8607`, `860A`, `8746`, `8747`, `8748`, `8749`, `874A`, `8786`, `8787`, `8788`, `878A`, `878B`, `878C`, `87B5`, `886B`, `886C`, `88C8`, `88CB`, `88D1`, `88D2`, `88F4`, `88F5`, `88F6`, `88F7`, `88FD`, `88FE`, `88FF`, `8900`, `8901`, `8902`, `8912`, `8917`, `8918`, `8949`, `894A`, `89EB`, `8A15`, `8A42`, `8BAD`, `8BAC`, `8C77`, `8D41`, `8E35`, `8E41`, `8BA9`

#### 强制使用 Omen 散热模式 V0 的主板组 (`omen_thermal_profile_force_v0_boards`)
这些主板将被强制使用 Omen 散热配置 V0 版本，不论 BIOS 返回的主板设计数据如何：
> `8607`, `8746`, `8747`, `8748`, `8749`, `874A`

#### 带有 EC 定时器的 Omen 主板组 (`omen_timed_thermal_profile_boards`)
这些设备在启用狂暴（性能）模式时会启动一个 120 秒的 EC 安全定时器。驱动程序会在后台持续重置此定时器，以使狂暴模式保持长效激活：
> `8A15`, `8A42`, `8BAD`

#### Victus 16-d 系列主板组 (`victus_thermal_profile_boards`)
使用第一代 Victus 散热模式控制方案的笔记本型号：
> `88F8`, `8A25`

---

## 4. 散热配置与十六进制值映射

Linux `platform_profile`（平台配置文件）子系统将用户空间选择的模式（Performance, Balanced 等）映射为 BIOS/EC 所期望的十六进制代码。不同世代和系列的设备，其对应代码不同。

### 4.1. 经典 / 标准 HP 散热模式
定义于 `enum hp_thermal_profile`：

| 模式名称 | 十六进制值 | Linux 模式 | 说明 |
| :--- | :---: | :--- | :--- |
| `HP_THERMAL_PROFILE_PERFORMANCE` | `0x00` | `performance` | 提供最大的 CPU/GPU 功耗预算，并开启积极的风扇曲线。 |
| `HP_THERMAL_PROFILE_DEFAULT` | `0x01` | `balanced` | 标准日常使用，在噪音和性能间取得平衡。 |
| `HP_THERMAL_PROFILE_COOL` | `0x02` | `cool` | 限制功耗以降低笔记本表面温度。 |
| `HP_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` | 最小化风扇噪声，应用较低的功耗限制。 |

### 4.2. HP Omen 系列模式

#### Omen V0 (旧代产品)
定义于 `enum hp_thermal_profile_omen_v0`：

| 模式名称 | 十六进制值 | Linux 模式 |
| :--- | :---: | :--- |
| `HP_OMEN_V0_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_OMEN_V0_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |
| `HP_OMEN_V0_THERMAL_PROFILE_COOL` | `0x02` | `cool` |

#### Omen V1 (现代产品)
定义于 `enum hp_thermal_profile_omen_v1`：

| 模式名称 | 十六进制值 | Linux 模式 |
| :--- | :---: | :--- |
| `HP_OMEN_V1_THERMAL_PROFILE_DEFAULT` | `0x30` | `balanced` |
| `HP_OMEN_V1_THERMAL_PROFILE_PERFORMANCE`| `0x31` | `performance` |
| `HP_OMEN_V1_THERMAL_PROFILE_COOL` | `0x50` | `cool` |

### 4.3. HP Victus 系列模式

#### 标准 Victus (16-d 系列)
定义于 `enum hp_thermal_profile_victus`：

| 模式名称 | 十六进制值 | Linux 模式 |
| :--- | :---: | :--- |
| `HP_VICTUS_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_VICTUS_THERMAL_PROFILE_PERFORMANCE` | `0x01` | `performance` |
| `HP_VICTUS_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` |

#### Victus S 系列 (16-r 和 16-s 系列)
定义于 `enum hp_thermal_profile_victus_s`：

| 模式名称 | 十六进制值 | Linux 模式 |
| :--- | :---: | :--- |
| `HP_VICTUS_S_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` 或 `low_power` (ECO)* |
| `HP_VICTUS_S_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |

> [!NOTE]
> *在 Victus S 系列型号上，平衡（`Balanced`）和安静（`Low Power` / ECO）模式在 EC 中映射为同一个值 `0x00`。驱动程序通过查询显卡功耗状态（cTGP 和 PPAB）来区分两者。如果两项显卡功耗都被禁用，则模式报告为 `low_power`（ECO 模式）；如果 PPAB 激活，则报告为 `balanced`（平衡）。

---

## 5. 显卡与功耗限制控制 (GPU & CPU PL1/PL2)

在现代的 Victus 和 Omen 笔记本电脑中，散热配置不仅控制风扇转速，还直接控制 CPU 和 GPU 的功耗包络（TGP/TDP）。

### 5.1. GPU 功耗管理 (cTGP 与 PPAB)
驱动程序使用 `HPWMI_SET_GPU_THERMAL_MODES_QUERY` (`0x22`) 控制 GPU 的功耗限制。`struct victus_gpu_power_modes` 包含以下参数：

| 参数 | 类型 | 功能与用途 |
| :--- | :--- | :--- |
| `ctgp_enable` | `u8` | **Configurable TGP:** 释放显卡的最大功耗上限（例如从 80W 提升至 120W）。在狂暴（性能）模式下置为 `0x01`（启用），在其他模式下为 `0x00`。 |
| `ppab_enable` | `u8` | **Dynamic Boost (PPAB):** 根据工作负载在 CPU 和 GPU 之间动态分配共享功耗。在安静（`Low Power`）模式下设为 `0x00`（禁用），在平衡和性能模式下设为 `0x01`。 |
| `dstate` | `u8` | **GPU 功耗路由优先级:** 默认值设置为 `1`（代表 100% 优先级）。 |
| `gpu_slowdown_temp` | `u8` | **GPU 降频温度点:** 从 BIOS 中读取并保留的显卡温度限制保护值。 |

### 5.2. CPU 功耗限制 (PL1 与 PL2)
在 Victus S 系列主板上，CPU 的 **PL1 (长期功耗限制)** 和 **PL2 (短期功耗限制)** 通过 `HPWMI_SET_POWER_LIMITS_QUERY` (`0x29`) 管理：
* `pl2` 值必须始终大于或等于 `pl1` (`pl2 >= pl1`)。
* 在电源源切换时（拔下或插上交流适配器），内核通知链处理器 (`victus_s_powersource_event`) 会自动重新应用默认的功耗上限 (`HP_POWER_LIMIT_DEFAULT` -> `0x00`），以防止使用电池时出现性能被强行限制无法恢复的问题。

---

## 6. 高级风扇控制 (Hwmon 框架)

驱动程序与 Linux 硬件监控子系统（`hwmon`）对接，暴露风扇转速，并允许用户手动覆写控制。

### 6.1. 风扇控制模式
手动和自动风扇控制由 `enum pwm_modes` 描述：

| 模式名称 | 模式值 | 说明 |
| :--- | :---: | :--- |
| `PWM_MODE_MAX` | `0` | **最大转速：** 强制风扇以 100% 满载负荷运行。 |
| `PWM_MODE_MANUAL` | `1` | **手动覆写：** 允许用户通过 sysfs 接口直接设置目标转速 (RPM)。 |
| `PWM_MODE_AUTO` | `2` | **EC 自动控制：** 将风扇控制完全交给嵌入式控制器的内部热温度算法。 |

### 6.2. 维持心跳看门狗定时器 (Keep-Alive Watchdog)
当进入手动风扇模式或最大风扇模式时，HP 嵌入式控制器 (EC) 会出于硬件安全考虑启动一个 **120 秒的安全倒计时器**。如果在此期间内未收到任何 WMI 风扇设置命令，EC 将自动恢复至自动模式 (`AUTO`）以保障硬件安全。

为了实现长效的手动风扇控制，驱动程序实现了一个后台看门狗工作任务（**Delayed Work - Keep Alive Watchdog**）：
* 驱动程序每隔 **90 秒** (`KEEP_ALIVE_DELAY_SECS = 90`) 悄悄地向硬件重新发送当前的风扇模式和转速命令。
* 这样做能连续重置 EC 的 120 秒安全定时器，从而保持手动覆写的激活状态。
* 用户将模式恢复为自动 (`AUTO`）后，心跳工作任务会被取消 (`cancel_delayed_work_sync`），控制权归还给 EC。

### 6.3. Victus S 风扇转速曲线表结构
在 Victus S 系列主板上，风扇限值从 BIOS 中通过 `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY` (`0x2F`) 查询所得：

```c
struct victus_s_fan_table_header {
    u8 unknown;
    u8 num_entries; // 转速曲线中的有效步骤数量
} __packed;

struct victus_s_fan_table_entry {
    u8 cpu_rpm;     // CPU 风扇转速 (值 * 100 RPM)
    u8 gpu_rpm;     // GPU 风扇转速 (值 * 100 RPM)
    u8 unknown;
} __packed;
```
* **最小限值边界：** 读取自转速曲线表中的第一行 (`entries[0].cpu_rpm`)。
* **最大限值边界：** 读取自转速曲线表中的最后一行 (`entries[num_entries-1]`)。
* **退化机制：** 如果主板不支持风扇转速表查询或数据格式损坏，驱动程序会在 probe 时自动启用一组 **5000 RPM 的硬安全应急限制** (`setup_fallback_fan_limits`）来代替，避免加载失败。

---

## 7. WMI 事件通知 (Event IDs)

驱动程序通过 `HPWMI_EVENT_GUID` 监听到的 ACPI 通知及其响应措施：

| 事件 ID (十六进制) | 事件名称 | 触发条件与驱动响应行为 |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DOCK_EVENT` | 连接/断开拓展坞或平板电脑模式改变。通过 `input_report_switch` 进行报告。 |
| `0x02` | `HPWMI_PARK_HDD` | 自由落体传感器警报；在冲击前紧急停靠机械硬盘磁头以保护数据。 |
| `0x03` | `HPWMI_SMART_ADAPTER` | 接入非原装或功率不足的充电器警告。 |
| `0x04` | `HPWMI_BEZEL_BUTTON` | 屏幕物理边框上的特殊物理按键；报告为键盘物理按键事件。 |
| `0x05` | `HPWMI_WIRELESS` | 无线设备状态开关事件（Wi-Fi、蓝牙、WWAN）；同步更新 rfkill 状态。 |
| `0x06` | `HPWMI_CPU_BATTERY_THROTTLE` | 由于 3 芯电池安全包络需要，CPU 被迫降低功耗。 |
| `0x0A` | `HPWMI_COOLSENSE_SYSTEM_MOBILE`| HP CoolSense: 检测到电脑置于大腿上，进一步降低设备表面温度。 |
| `0x0B` | `HPWMI_COOLSENSE_SYSTEM_HOT` | HP CoolSense: 检测到设备置于桌面上，允许最大性能运行。 |
| `0x0D` | `HPWMI_BACKLIT_KB_BRIGHTNESS` | 键盘背光亮度等级已更新。 |
| `0x1A` | `HPWMI_CAMERA_TOGGLE` | **摄像头隐私遮蔽罩切换：** 摄像头物理拨片开关状态已更新（`0xFF`: 遮蔽, `0xFE`: 开启）。报告 Linux 内核标准的 `SW_CAMERA_LENS_COVER` 信号。 |
| `0x1B` | `HPWMI_FN_P_HOTKEY` | **Fn + P 组合键事件：** 按下后将在平台散热配置文件中循环切换 (`platform_profile_cycle`)。 |
| `0x1D` | `HPWMI_OMEN_KEY` | **Omen 专用徽标键：** 按下后会向系统发送按键事件 `KEY_PROG2`（用以调起暗影精灵游戏中心）。 |

---

## 8. 驱动程序 WMI 命令与查询类型参考

驱动程序在评估 BIOS WMI 方法 (`hp_wmi_perform_query`) 时所用指令及查询码如下：

### 8.1. WMI 查询指令类型 (`enum hp_wmi_commandtype`)
用作 `hp_wmi_perform_query` 函数的第一个参数 `query`：

| 十六进制码 | 查询指令名称 (宏定义) | 具体用途 |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DISPLAY_QUERY` | 获取或改变显示输出状态。 |
| `0x02` | `HPWMI_HDDTEMP_QUERY` | 查询机械硬盘物理温度传感器。 |
| `0x03` | `HPWMI_ALS_QUERY` | 环境光线感应器（Ambient Light Sensor）控制器。 |
| `0x04` | `HPWMI_HARDWARE_QUERY` | 查询机械转接坞与平板模式连接状态。 |
| `0x05` | `HPWMI_WIRELESS_QUERY` | 旧代设备上的物理无线状态硬开关。 |
| `0x07` | `HPWMI_BATTERY_QUERY` | 获取电池健康等级和具体性能参数。 |
| `0x09` | `HPWMI_BIOS_QUERY` | 写入 `0x6E` 以在 BIOS 中激活键盘快捷键功能。 |
| `0x0B` | `HPWMI_FEATURE_QUERY` | 查询 2008 年之后版本的 BIOS 特性集支持情况。 |
| `0x0C` | `HPWMI_HOTKEY_QUERY` | 读取所按下专用热键对应的内部键码值。 |
| `0x0D` | `HPWMI_FEATURE2_QUERY` | 查询 2009 年之后版本的 BIOS 进阶特性集。 |
| `0x1B` | `HPWMI_WIRELESS2_QUERY` | 现代多通道无线设备总管（rfkill2 状态）。 |
| `0x2A` | `HPWMI_POSTCODEERROR_QUERY` | 读写 BIOS POST 自检错误信息。 |
| `0x40` | `HPWMI_SYSTEM_DEVICE_MODE` | 显卡直连切换（MUX Switch）与平板模式状态检测。 |
| `0x4C` | `HPWMI_THERMAL_PROFILE_QUERY` | 读写经典的系统散热工作模式。 |

### 8.2. 暗影精灵 / 游戏本专有查询指令 (`enum hp_wmi_gm_commandtype`)
由游戏控制中心派生出来的 WMI 指令集，用以调节性能增幅相关特性：

| 十六进制码 | 查询指令名称 (宏定义) | 具体用途 |
| :---: | :--- | :--- |
| `0x10` | `HPWMI_FAN_COUNT_GET_QUERY` | 获取主板风扇计数，并会在 EC 中触发开启“用户自定义风扇状态”。 |
| `0x11` | `HPWMI_FAN_SPEED_GET_QUERY` | 获取经典设备上的风扇转速。 |
| `0x1A` | `HPWMI_SET_PERFORMANCE_MODE` | 将 Omen 专有散热模式标志下发写入至 EC。 |
| `0x21` | `HPWMI_GET_GPU_THERMAL_MODES_QUERY`| 获取显卡（GPU）的 cTGP 与 PPAB 状态。 |
| `0x22` | `HPWMI_SET_GPU_THERMAL_MODES_QUERY`| 设置下发显卡 cTGP 与 PPAB 功耗包络。 |
| `0x26` | `HPWMI_FAN_SPEED_MAX_GET_QUERY` | 查询硬件的最大风扇模式是否处于打开状态。 |
| `0x27` | `HPWMI_FAN_SPEED_MAX_SET_QUERY` | 开关最大风扇模式 (`0x01` 代表强制最高风扇，`0x00` 代表关闭）。 |
| `0x28` | `HPWMI_GET_SYSTEM_DESIGN_DATA` | 探测主板上预存的 Omen 散热模式协议版本（V0 或 V1）。 |
| `0x29` | `HPWMI_SET_POWER_LIMITS_QUERY` | 手动覆写 CPU PL1 以及 PL2 的功耗包络阈值。 |
| `0x2D` | `HPWMI_VICTUS_S_FAN_SPEED_GET_QUERY`| 在 Victus S 系列主板上双风扇转速同步抓取读取。 |
| `0x2E` | `HPWMI_VICTUS_S_FAN_SPEED_SET_QUERY`| 向 Victus S 主板双通道手动注入风扇转速。 |
| `0x2F` | `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY`| 从 BIOS 固件中抓取原始风扇转速梯形表。 |

---

## 9. 硬件适配问题及相关修复 yamashis (Fixes)

为了提高不同硬件平台的兼容性，该驱动程序引入了以下重要修复：

### 1. NVIDIA 显卡 Dynamic Boost 功耗限制修复 (xcellsior 补丁)
* **硬件故障：** 在没有明确定位 EC 排布的机型中（例如 HP 暗影精灵 Max 16, 主板 `8D41`），驱动在 probe 加载过程中进行的初始化 WMI 风扇控制写入，会导致 ACPI 固件内部强行将 NVIDIA Dynamic Boost DC 功耗路由控制器关闭，使得显卡功耗（TGP）被死死锁死在基础瓦数（例如原本应为 120W 的显卡被限制在 80W）。
* **修复方法：** 驱动加入了规避逻辑，若设备检测到的 EC 散热偏移量为 `HP_EC_OFFSET_UNKNOWN`（代表未验证主板），驱动在加载期间绝对不往主板下发任何风扇同步包。风扇模式的强制对齐将延期到用户在 sysfs 接口处下发第一次 `pwm_enable` 写入时进行，从而完全防止了显卡功耗锁死的情况。

### 2. ACPI GETB 主板固件崩溃崩溃绕过 (主板 8BAC)
* **硬件故障：** `8BAC` 主板（HP 暗影精灵 16-wf0xxx）的 ACPI DSDT 代码中的辅助函数 `GETB` 内部编写存在严重的硬件 bug（试图创建零长度的内部控制字段）。这导致系统每次发起散热 WMI 请求时，ACPI 控制栈都会发生溢出终止，导致整个 ACPI 系统瘫痪引发死机。
* **修复方法：** 该主板型号被明确绑定为 `omen_v1_no_ec_thermal_params`。在该设备上，驱动会主动跳过所有直接对 EC 散热偏移量的读取过程，完全由之前软件内侧缓存的状态来充当读数，彻底确保了系统的极其稳定。

### 3. 摄像头镜头物理遮蔽罩关联接口 (`camera_shutter_input_setup`)
* **硬件需求：** 对带有摄像头实体防窥开关的机型，需要与用户空间的桌面环境进行交互，及时警告摄像头遮蔽罩已拉上。
* **修复方法：** 驱动初始化时注册一个名为 `HP WMI camera shutter` 的虚拟输入设备。每当事件 `0x1A` 触发时，驱动将抓取拨片物理覆盖状态（`0xFF` 为被遮蔽，`0xFE` 为敞开）并将其作为 Linux 系统标准的按键开关事件 `SW_CAMERA_LENS_COVER` 瞬时报告给内核。
