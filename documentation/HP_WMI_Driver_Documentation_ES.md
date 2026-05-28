# Documentación Técnica Detallada del Controlador HP WMI (hp-wmi.c)

Este documento contiene un análisis detallado y una referencia técnica para el controlador del kernel `hp-wmi.c`, que administra el control de hardware, la gestión térmica, el control de ventiladores y los atajos especiales del teclado para computadoras portátiles HP (especialmente las series **OMEN** y **Victus**) en el kernel de Linux.

---

## 1. Introducción y Arquitectura del Controlador

`hp-wmi.c` es un controlador del kernel que expone la interfaz **WMI (Windows Management Instrumentation)** de los dispositivos HP a la plataforma Linux. El controlador utiliza dos GUID (Identificadores Únicos Globales) de WMI principales para controlar las características del hardware e interceptar eventos ACPI:

| Macro GUID | Valor de Cadena GUID | Función / Propósito |
| :--- | :--- | :--- |
| `HPWMI_EVENT_GUID` | `"95F24279-4D7B-4334-9387-ACCDC67EF61C"` | Informa eventos como atajos de teclado, interruptor de la tapa y eventos de conexión del cargador. |
| `HPWMI_BIOS_GUID` | `"5FB7F034-2C63-45E9-BE91-3D44E2C707E4"` | Lectura/escritura de velocidad de ventiladores, temperaturas, modos de tarjeta gráfica y perfiles térmicos. |

El controlador se comunica con la BIOS y el **Controlador Embebido (EC - Embedded Controller)** llamando a la función `hp_wmi_perform_query` para leer estados de hardware (`HPWMI_READ`) o escribir nuevas configuraciones (`HPWMI_WRITE` / `HPWMI_GM`).

---

## 2. Desplazamientos (Offsets) del Controlador Embebido (EC)

Se accede a registros específicos (desplazamientos) en el Controlador Embebido (EC) del dispositivo para leer y escribir perfiles térmicos. Estos offsets se definen bajo `enum hp_ec_offsets`.

### Nombres y Descripciones de los Offsets del EC

| Nombre del Offset del EC | Dirección Hex | Descripción y Propósito |
| :--- | :---: | :--- |
| `HP_EC_OFFSET_UNKNOWN` | `0x00` | **Distribución de EC Desconocida:** La lectura del perfil térmico basada en DMI está deshabilitada en placas con este desplazamiento. Se selecciona el modo equilibrado (`BALANCED`) de forma predeterminada al arrancar en frío. |
| `HP_NO_THERMAL_PROFILE_OFFSET` | `0x01` | **Sin Perfil Térmico:** Omite las lecturas del perfil térmico del EC por completo. Se usa en modelos nuevos específicos con tablas ACPI rotas para evitar el bloqueo de consultas. |
| `HP_VICTUS_S_EC_THERMAL_PROFILE_OFFSET` | `0x59` | **Dirección del Perfil Térmico de la Serie Victus S:** Celda de memoria del EC principal que almacena el estado del perfil térmico en las placas madre modernas Victus 16 (series r y s) y algunas Omen V1. |
| `HP_OMEN_EC_THERMAL_PROFILE_FLAGS_OFFSET` | `0x62` | **Dirección de Banderas del Perfil Térmico Omen:** Celda de bandera especial utilizada en dispositivos Omen para habilitar el modo Turbo (`0x04`) o deshabilitar el temporizador del EC (`0x02`). |
| `HP_OMEN_EC_THERMAL_PROFILE_TIMER_OFFSET` | `0x63` | **Dirección del Temporizador del Perfil Térmico Omen:** Celda del temporizador del EC administrada por Omen Gaming Hub; cuando llega a cero, el EC restablece el perfil a "Equilibrado". |
| `HP_OMEN_EC_THERMAL_PROFILE_OFFSET` | `0x95` | **Dirección de Perfil Térmico Clásico de Omen:** El registro de estado del perfil utilizado en los Omen heredados (V1 Legacy) y algunos modelos Victus más antiguos. |

---

## 3. Placas Base (DMI Boards) y Mapeos de Desplazamiento

El controlador lee el identificador de la placa base del sistema (**DMI Board Name**) para determinar qué desplazamientos de EC y parámetros térmicos aplicar.

### 3.1. Tabla de Mapeo de Parámetros de Placa Base Victus y Omen

Las placas base definidas en el arreglo `victus_s_thermal_profile_boards`, junto con sus parámetros térmicos asignados y desplazamientos de EC, se enumeran a continuación:

| ID de Placa (DMI Board Name) | Modelo / Serie de Laptop Asociada | Estructura de Parámetros Térmicos | Offset del Perfil del EC | Valor de Performance | Valor de Balanced | Valor de Low Power | Descripción / Casos Especiales |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **8A13** | OMEN by HP Laptop 16-b1xxx | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Placa base que utiliza el diseño clásico Omen V1. |
| **8A4D** | HP Omen Seria | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Diseño clásico Omen V1. |
| **8BAB** | HP Omen Seria | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Placa base Omen que utiliza el offset moderno 0x59. |
| **8BBE** | HP Victus Seria | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Distribución de EC desconocida (0x00). Se utiliza almacenamiento en caché de perfiles por software. |
| **8BCA** | HP Omen Seria | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Offset moderno 0x59. |
| **8BCD** | HP Omen Seria | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Offset moderno 0x59. |
| **8BD4** | HP Victus Seria | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Distribución de EC desconocida (0x00). |
| **8BD5** | HP Victus Seria | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Distribución de EC desconocida (0x00). |
| **8C76** | HP Omen Seria | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Offset moderno 0x59. |
| **8C77** | HP Omen Seria | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Omen moderno que utiliza el offset clásico 0x95. |
| **8C78** | HP Omen Seria | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Offset moderno 0x59. |
| **8E35** | HP Omen Seria | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Offset moderno 0x59. |
| **8C99** | HP Victus Seria | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Distribución de EC desconocida (0x00). |
| **8C9C** | HP Victus Seria (ej: 16-s1034nf) | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Distribución de EC desconocida (0x00). Requiere actualización de PL1/PL2 al cambiar de fuente de energía. |
| **8D41** | HP Omen Max (ej: 16-u0xxx) | `omen_v1_unknown_ec_thermal_params`| `0x00` | `0x31` | `0x30` | `0x30` | Diseño Omen V1 pero con offset de EC desconocido. |
| **8D87** | HP Omen Seria | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | Placa base con lecturas del EC deshabilitadas. |
| **8BA9** | HP Omen Seria | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Diseño clásico Omen V1. |
| **8BAC** | HP Omen 16-wf0xxx | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | **Error Crítico de ACPI:** Las tablas ACPI tienen una función GETB defectuosa (error de creación de campo de longitud cero) que cancela las consultas de WMI. Se omiten las lecturas del EC para evitar bloqueos. |
| **8BC2** | Victus by HP Gaming Laptop 16-r0xxx| `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Distribución de EC desconocida (0x00). |

---

### 3.2. Otros Grupos Especializados de Placas DMI

#### Placas con Soporte para Perfil Térmico Omen (`omen_thermal_profile_boards`)
Estos nombres de placa se compilan a partir de la lista de capacidades del Omen Command Center y utilizan rutas de perfiles térmicos específicos de Omen:
> `84DA`, `84DB`, `84DC`, `8572`, `8573`, `8574`, `8575`, `8600`, `8601`, `8602`, `8603`, `8604`, `8605`, `8606`, `8607`, `860A`, `8746`, `8747`, `8748`, `8749`, `874A`, `8786`, `8787`, `8788`, `878A`, `878B`, `878C`, `87B5`, `886B`, `886C`, `88C8`, `88CB`, `88D1`, `88D2`, `88F4`, `88F5`, `88F6`, `88F7`, `88FD`, `88FE`, `88FF`, `8900`, `8901`, `8902`, `8912`, `8917`, `8918`, `8949`, `894A`, `89EB`, `8A15`, `8A42`, `8BAD`, `8BAC`, `8C77`, `8D41`, `8E35`, `8E41`, `8BA9`

#### Placas Omen Forzadas al Perfil Térmico V0 (`omen_thermal_profile_force_v0_boards`)
Estas placas son forzadas a utilizar la versión 0 del perfil térmico Omen, independientemente de los datos de diseño del sistema devueltos por la BIOS:
> `8607`, `8746`, `8747`, `8748`, `8749`, `874A`

#### Placas Omen con Temporizadores de EC (`omen_timed_thermal_profile_boards`)
Estos dispositivos inician un temporizador de EC de 120 segundos cuando se habilita el modo de rendimiento. El controlador restablece continuamente este temporizador para mantener activo el modo de rendimiento:
> `8A15`, `8A42`, `8BAD`

#### Placas de la Serie Victus 16-d (`victus_thermal_profile_boards`)
Modelos que utilizan el esquema de control del perfil térmico Victus de primera generación:
> `88F8`, `8A25`

---

## 4. Perfiles Térmicos y Mapeos Hexadecimales

La interfaz `platform_profile` de Linux mapea los perfiles de usuario (Performance, Balanced, etc.) a los códigos hexadecimales esperados por la BIOS/EC. Estos códigos varían según las diferentes generaciones y series de dispositivos.

### 4.1. Perfiles Clásicos / Estándar de HP
Definidos en `enum hp_thermal_profile`:

| Nombre del Perfil | Valor Hex | Perfil de Linux | Descripción |
| :--- | :---: | :--- | :--- |
| `HP_THERMAL_PROFILE_PERFORMANCE` | `0x00` | `performance` | Presupuesto máximo de energía de CPU/GPU y curvas de ventilador agresivas. |
| `HP_THERMAL_PROFILE_DEFAULT` | `0x01` | `balanced` | Uso diario estándar, potencia y ruido equilibrados. |
| `HP_THERMAL_PROFILE_COOL` | `0x02` | `cool` | Límites de energía más bajos para mantener bajas las temperaturas de la superficie de la laptop. |
| `HP_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` | Ruido mínimo del ventilador mediante topes de energía reducidos. |

### 4.2. Perfiles de HP Omen

#### Omen V0 (Generación Anterior)
Definidos en `enum hp_thermal_profile_omen_v0`:

| Nombre del Perfil | Valor Hex | Perfil de Linux |
| :--- | :---: | :--- |
| `HP_OMEN_V0_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_OMEN_V0_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |
| `HP_OMEN_V0_THERMAL_PROFILE_COOL` | `0x02` | `cool` |

#### Omen V1 (Generación Moderna)
Definidos en `enum hp_thermal_profile_omen_v1`:

| Nombre del Perfil | Valor Hex | Perfil de Linux |
| :--- | :---: | :--- |
| `HP_OMEN_V1_THERMAL_PROFILE_DEFAULT` | `0x30` | `balanced` |
| `HP_OMEN_V1_THERMAL_PROFILE_PERFORMANCE`| `0x31` | `performance` |
| `HP_OMEN_V1_THERMAL_PROFILE_COOL` | `0x50` | `cool` |

### 4.3. Perfiles de HP Victus

#### Victus Estándar (Serie 16-d)
Definidos en `enum hp_thermal_profile_victus`:

| Nombre del Perfil | Valor Hex | Perfil de Linux |
| :--- | :---: | :--- |
| `HP_VICTUS_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_VICTUS_THERMAL_PROFILE_PERFORMANCE` | `0x01` | `performance` |
| `HP_VICTUS_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` |

#### Serie Victus S (Series 16-r y 16-s)
Definidos en `enum hp_thermal_profile_victus_s`:

| Nombre del Perfil | Valor Hex | Perfil de Linux |
| :--- | :---: | :--- |
| `HP_VICTUS_S_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` o `low_power` (ECO)* |
| `HP_VICTUS_S_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |

> [!NOTE]
> *En los modelos de la serie Victus S, los perfiles `Balanced` y `Low Power` se mapean a `0x00` en el EC. El controlador se diferencia entre ellos consultando los estados de energía de la GPU (cTGP y PPAB). Si ambos están deshabilitados, el modo se informa como `low_power` (ECO); si PPAB está activo, se informa como `balanced`.

---

## 5. Controles de Gráficos y Límites de Energía (GPU & CPU PL1/PL2)

En las laptops Victus y Omen modernas, los perfiles térmicos gobiernan no solo las curvas del ventilador sino también los límites de energía de la CPU y la GPU (TGP/TDP).

### 5.1. Gestión de Energía de la GPU (cTGP y PPAB)
El controlador administra los límites de energía de la GPU utilizando `HPWMI_SET_GPU_THERMAL_MODES_QUERY` (`0x22`). La estructura `struct victus_gpu_power_modes` controla los siguientes parámetros:

| Parámetro | Tipo | Función / Comportamiento |
| :--- | :--- | :--- |
| `ctgp_enable` | `u8` | **Configurable TGP:** Desata el límite máximo de energía de la tarjeta gráfica (ej: 120W en lugar de 80W). Se establece en `0x01` (habilitado) en modo de rendimiento (`Performance`), y `0x00` en caso contrario. |
| `ppab_enable` | `u8` | **Dynamic Boost (PPAB):** Equilibra el uso compartido dinámico de energía entre CPU y GPU en función de la carga de trabajo. Se establece en `0x00` (deshabilitado) en modo de bajo consumo (`Low Power`), y `0x01` en modos equilibrado (`Balanced`) y rendimiento (`Performance`). |
| `dstate` | `u8` | **Prioridad de Energía de la GPU:** Define la prioridad de enrutamiento de energía (El valor predeterminado es `1`, que representa el 100% de prioridad). |
| `gpu_slowdown_temp` | `u8` | **Temperatura de Desaceleración de GPU:** Límite de estrangulamiento térmico leído desde la BIOS y preservado durante las escrituras. |

### 5.2. Límites de Energía de la CPU (PL1 y PL2)
En las placas de la serie Victus S, el **PL1 (Límite de Energía a Largo Plazo)** y **PL2 (Límite de Energía a Corto Plazo)** de la CPU se gestionan a través de `HPWMI_SET_POWER_LIMITS_QUERY` (`0x29`):
* `pl2` siempre debe ser mayor o igual que `pl1` (`pl2 >= pl1`).
* Durante las transiciones de la fuente de alimentación (conectar/desconectar el cargador de CA), un notificador (`victus_s_powersource_event`) vuelve a aplicar automáticamente los límites de energía predeterminados (`HP_POWER_LIMIT_DEFAULT` -> `0x00`) para evitar bloqueos del rendimiento con la energía de la batería.

---

## 6. Control Avanzado del Ventilador (Marco Hwmon)

El controlador interactúa con el subsistema de monitoreo de hardware de Linux (`hwmon`) para exponer lecturas de velocidad del ventilador y habilitar capacidades de anulación manual.

### 6.1. Modos de Control del Ventilador
El control manual y automático del ventilador se define bajo `enum pwm_modes`:

| Nombre del Modo | Valor | Descripción |
| :--- | :---: | :--- |
| `PWM_MODE_MAX` | `0` | **Ventilador Máximo:** Fuerza a los ventiladores a funcionar al 100% de su ciclo de trabajo. |
| `PWM_MODE_MANUAL` | `1` | **Anulación Manual:** Permite a los usuarios establecer directamente las RPM objetivo del ventilador a través de sysfs. |
| `PWM_MODE_AUTO` | `2` | **Control Automático del EC:** Cede el control a los algoritmos térmicos internos del Controlador Embebido. |

### 6.2. Temporizador Guardián de Keep-Alive
El Controlador Embebido (EC) de HP inicia un **temporizador de seguridad de 120 segundos** al ingresar al modo de ventilador manual o al modo de ventilador máximo. Si no se reciben comandos de WMI en 120 segundos, el EC vuelve al modo automático (`AUTO`) por seguridad.

Para evitar esto, el controlador ejecuta un hilo de guardián en segundo plano (**Delayed Work - Keep Alive Watchdog**):
* El controlador emite una actualización de keep-alive cada **90 segundos** (`KEEP_ALIVE_DELAY_SECS = 90`), escribiendo el modo y las velocidades activas de vuelta al EC.
* Esto restablece constantemente el temporizador de seguridad de 120 segundos del EC, manteniendo activo el control manual.
* Cuando el usuario vuelve a `AUTO`, el hilo del guardián se cancela (`cancel_delayed_work_sync`) y el EC toma el control.

### 6.3. Estructura de la Tabla de Ventiladores de Victus S
En las laptops de la serie Victus S, los límites de velocidad del ventilador se extraen de la BIOS a través de `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY` (`0x2F`):

```c
struct victus_s_fan_table_header {
    u8 unknown;
    u8 num_entries; // Número de entradas en la curva del ventilador
} __packed;

struct victus_s_fan_table_entry {
    u8 cpu_rpm;     // Velocidad del ventilador de la CPU (valor * 100 RPM)
    u8 gpu_rpm;     // Velocidad del ventilador de la GPU (valor * 100 RPM)
    u8 unknown;
} __packed;
```
* **Límites Mínimos:** Extraídos del primer paso en la tabla (`entries[0].cpu_rpm`).
* **Límites Máximos:** Extraídos del último paso (`entries[num_entries-1]`).
* **Degradación Gradual:** Si la consulta de la tabla de ventiladores no es compatible o está malformada, el controlador registra automáticamente una **tabla de respaldo segura de 5000 RPM** (`setup_fallback_fan_limits`) en lugar de fallar la inicialización.

---

## 7. Notificaciones de Eventos WMI (Event IDs)

Notificaciones ACPI recibidas a través de `HPWMI_EVENT_GUID` y respuesta del controlador:

| ID de Evento (Hex) | Nombre del Evento | Condición de Activación y Comportamiento del Controlador |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DOCK_EVENT` | Acoplamiento/desacoplamiento o transición al modo tablet. Reportado a través de `input_report_switch`. |
| `0x02` | `HPWMI_PARK_HDD` | Alerta del sensor de caída libre; estaciona el cabezal del HDD para proteger los datos. |
| `0x03` | `HPWMI_SMART_ADAPTER` | Advertencia de cargador no original o de baja potencia. |
| `0x04` | `HPWMI_BEZEL_BUTTON` | Pulsaciones especiales de atajos en el marco de la pantalla; reportadas como un evento de tecla. |
| `0x05` | `HPWMI_WIRELESS` | Conmutadores de estado inalámbrico (Wi-Fi, Bluetooth, WWAN); actualiza los estados de rfkill. |
| `0x06` | `HPWMI_CPU_BATTERY_THROTTLE` | Límites de energía de la CPU reducidos debido a la seguridad de la batería de 3 celdas. |
| `0x0A` | `HPWMI_COOLSENSE_SYSTEM_MOBILE` | HP CoolSense: La laptop está en el regazo, las temperaturas de la superficie se reducen. |
| `0x0B` | `HPWMI_COOLSENSE_SYSTEM_HOT` | HP CoolSense: La laptop está en un escritorio, se permite el rendimiento máximo. |
| `0x0D` | `HPWMI_BACKLIT_KB_BRIGHTNESS` | Niveles de brillo del teclado retroiluminado actualizados. |
| `0x1A` | `HPWMI_CAMERA_TOGGLE` | **Estado del Obturador de la Cámara:** Se cambió el estado de la cubierta física de la lente (`0xFF`: Cerrado, `0xFE`: Abierto). Informa el código de Linux estándar `SW_CAMERA_LENS_COVER`. |
| `0x1B` | `HPWMI_FN_P_HOTKEY` | **Combinación Fn + P:** Realiza un ciclo a través de las opciones de perfil de plataforma (`platform_profile_cycle`). |
| `0x1D` | `HPWMI_OMEN_KEY` | **Tecla Omen:** Lanza el Omen Gaming Hub; reportada como `KEY_PROG2`. |

---

## 8. Referencias de Comandos y Consultas WMI del Controlador

A continuación se muestra una referencia de los comandos WMI y tipos de consulta utilizados en las peticiones (`hp_wmi_perform_query`):

### 8.1. Tipos de Consulta WMI (`enum hp_wmi_commandtype`)
Pasado como primer argumento (`query`) a `hp_wmi_perform_query`:

| Código Hex | Nombre de la Consulta (Macro) | Propósito |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DISPLAY_QUERY` | Obtener el estado de la pantalla. |
| `0x02` | `HPWMI_HDDTEMP_QUERY` | Consultar sensores de temperatura del HDD. |
| `0x03` | `HPWMI_ALS_QUERY` | Controles del sensor de luz ambiental. |
| `0x04` | `HPWMI_HARDWARE_QUERY` | Consulta de estados de tableta y acoplamiento. |
| `0x05` | `HPWMI_WIRELESS_QUERY` | Estados de interruptores inalámbricos de generación anterior. |
| `0x07` | `HPWMI_BATTERY_QUERY` | Leer la salud y métricas de la batería. |
| `0x09` | `HPWMI_BIOS_QUERY` | Habilitar funciones de atajos de BIOS (escribe `0x6E`). |
| `0x0B` | `HPWMI_FEATURE_QUERY` | Consultar conjuntos de características de BIOS posteriores a 2008. |
| `0x0C` | `HPWMI_HOTKEY_QUERY` | Leer el código de tecla del atajo presionado. |
| `0x0D` | `HPWMI_FEATURE2_QUERY` | Consultar conjuntos de características avanzadas de BIOS posteriores a 2009. |
| `0x1B` | `HPWMI_WIRELESS2_QUERY` | Administrador moderno del estado inalámbrico multidispositivo (rfkill2). |
| `0x2A` | `HPWMI_POSTCODEERROR_QUERY` | Leer y limpiar los códigos de error POST de la BIOS. |
| `0x40` | `HPWMI_SYSTEM_DEVICE_MODE` | Conmutador de modo gráfico (Mux Switch) y detección de modo tableta. |
| `0x4C` | `HPWMI_THERMAL_PROFILE_QUERY` | Leer/escribir perfiles térmicos clásicos. |

### 8.2. Consultas Específicas de Omen / Gaming (`enum hp_wmi_gm_commandtype`)
Consultas del Gaming Command Center utilizadas para gestionar características de rendimiento:

| Código Hex | Nombre de la Consulta (Macro) | Propósito |
| :---: | :--- | :--- |
| `0x10` | `HPWMI_FAN_COUNT_GET_QUERY` | Lee el recuento de ventiladores. Activa el "modo de ventilador definido por el usuario" del EC. |
| `0x11` | `HPWMI_FAN_SPEED_GET_QUERY` | Leer la velocidad del ventilador clásica. |
| `0x1A` | `HPWMI_SET_PERFORMANCE_MODE` | Escribir perfiles térmicos de Omen en el EC. |
| `0x21` | `HPWMI_GET_GPU_THERMAL_MODES_QUERY`| Leer estados cTGP y PPAB de la GPU. |
| `0x22` | `HPWMI_SET_GPU_THERMAL_MODES_QUERY`| Escribir límites cTGP y PPAB de la GPU. |
| `0x26` | `HPWMI_FAN_SPEED_MAX_GET_QUERY` | Consultar si el modo de ventilador máximo está activo. |
| `0x27` | `HPWMI_FAN_SPEED_MAX_SET_QUERY` | Alternar el modo de ventilador máximo (`0x01` para habilitar, `0x00` para deshabilitar). |
| `0x28` | `HPWMI_GET_SYSTEM_DESIGN_DATA` | Obtener la versión de diseño del sistema (Omen V0 o V1). |
| `0x29` | `HPWMI_SET_POWER_LIMITS_QUERY` | Configurar los umbrales PL1 y PL2 de la CPU. |
| `0x2D` | `HPWMI_VICTUS_S_FAN_SPEED_GET_QUERY`| Leer simultáneamente las RPM de la CPU y GPU en la serie Victus S. |
| `0x2E` | `HPWMI_VICTUS_S_FAN_SPEED_SET_QUERY`| Anular directamente las RPM del ventilador en la serie Victus S. |
| `0x2F` | `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY`| Leer los límites de la curva escalonada del ventilador de la BIOS. |

---

## 9. Errores Críticos y Soluciones Alternativas (Fixes)

Con el tiempo, se han integrado varias soluciones de compatibilidad de hardware en el controlador:

### 1. Solución para el Límite de Energía GPU por NVIDIA Dynamic Boost (parche xcellsior)
* **Problema:** En placas con distribuciones de EC no caracterizadas (ej: HP Omen Max 16, placa `8D41`), enviar paquetes de control WMI del ventilador durante la carga del módulo deshabilitaba el controlador NVIDIA Dynamic Boost DC, limitando el objetivo de potencia de la GPU (TGP) a su nivel base (ej: 80W en lugar de 120W).
* **Solución:** El controlador omite la reconciliación inicial del modo de ventilador WMI si el offset del EC es `HP_EC_OFFSET_UNKNOWN`. La sincronización del modo del ventilador se pospone hasta la primera escritura del usuario en sysfs `pwm_enable`, preservando la potencia máxima de la GPU.

### 2. Prevención de Bloqueos por el Método ACPI GETB (Placa 8BAC)
* **Problema:** Las placas madre HP Omen 16-wf0xxx (`8BAC`) contienen un error de ACPI DSDT en su asistente `GETB`, intentando crear un campo de longitud cero. Esto causaba que las evaluaciones del método WMI fallaran, bloqueando el subsistema ACPI.
* **Solución:** La placa se mapea explícitamente a `omen_v1_no_ec_thermal_params`. El controlador omite toda lectura del perfil térmico basado en EC, confiando en las configuraciones almacenadas en caché para mantener la estabilidad del sistema.

### 3. Obturador de Privacidad de la Lente de la Cámara (`camera_shutter_input_setup`)
* **Problema:** Los modelos con interruptores físicos de privacidad requerían la integración con la interfaz de usuario para avisar cuando la cámara estaba bloqueada.
* **Solución:** El controlador registra un dispositivo de entrada virtual `HP WMI camera shutter`. Cuando se activa el evento `0x1A`, se analiza el estado de la cubierta de la lente (`0xFF` para cerrado, `0xFE` para abierto) y se mapea al código de tecla estándar del kernel de Linux `SW_CAMERA_LENS_COVER`.
