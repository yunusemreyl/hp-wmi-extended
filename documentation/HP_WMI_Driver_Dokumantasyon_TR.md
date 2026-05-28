# HP WMI Sürücüsü (hp-wmi.c) Detaylı Teknik Dokümantasyonu

Bu doküman, HP dizüstü bilgisayarlarının (özellikle **OMEN** ve **Victus** serileri) Linux çekirdeğindeki donanım kontrolünü, termal yönetimini, fan denetimini ve özel klavye kısayollarını yöneten `hp-wmi.c` çekirdek sürücüsünün detaylı analizini ve teknik referansını içerir.

---

## 1. Giriş ve Sürücü Mimarisi

`hp-wmi.c`, HP cihazlarındaki **WMI (Windows Management Instrumentation)** arayüzünü Linux platformuna taşıyan bir çekirdek sürücüsüdür. Sürücü, donanım özelliklerini kontrol etmek ve ACPI olaylarını yakalamak için iki ana WMI GUID'si (Globally Unique Identifier) kullanır:

| GUID Makrosu | GUID String Değeri | İşlevi |
| :--- | :--- | :--- |
| `HPWMI_EVENT_GUID` | `"95F24279-4D7B-4334-9387-ACCDC67EF61C"` | Klavye kısayolları, kapak anahtarı, şarj cihazı takılması gibi olayların bildirilmesi. |
| `HPWMI_BIOS_GUID` | `"5FB7F034-2C63-45E9-BE91-3D44E2C707E4"` | Fan hızları, sıcaklıklar, ekran kartı modları ve termal profillerin okunması/yazılması. |

Sürücü, donanım durumlarını sorgulamak (`HPWMI_READ`) ve yeni ayarlar uygulamak (`HPWMI_WRITE` / `HPWMI_GM`) için `hp_wmi_perform_query` fonksiyonunu kullanır. Bu sorgular, ACPI metotları aracılığıyla doğrudan BIOS ve **Embedded Controller (EC - Gömülü Denetleyici)** ile iletişim kurar.

---

## 2. Gömülü Denetleyici (EC - Embedded Controller) Ofsetleri

Sürücüde, cihazın gömülü denetleyicisindeki (EC) belirli adreslere (ofsetler) erişilerek termal profiller okunur ve yazılır. Bu adresler `enum hp_ec_offsets` altında tanımlanmıştır.

### EC Ofsetleri ve Görevleri

| EC Ofset İsmi | Hex Adresi | Açıklama ve Görevi |
| :--- | :---: | :--- |
| `HP_EC_OFFSET_UNKNOWN` | `0x00` | **Bilinmeyen EC Düzeni:** Bu ofsete sahip anakartlarda DMI tabanlı termal profil okuma devre dışı bırakılır. Soğuk önyüklemede varsayılan olarak `BALANCED` mod seçilir. |
| `HP_NO_THERMAL_PROFILE_OFFSET` | `0x01` | **Termal Profil Yok:** EC üzerinden doğrudan okuma yapılmasını engeller. Örneğin, ACPI tabloları hatalı olan bazı yeni modellerde kullanılır. |
| `HP_VICTUS_S_EC_THERMAL_PROFILE_OFFSET` | `0x59` | **Victus S-Serisi Termal Profil Adresi:** Modern Victus 16 (r ve s serileri) ile bazı Omen V1 anakartlarında termal profil durumunu saklayan ana EC bellek hücresi. |
| `HP_OMEN_EC_THERMAL_PROFILE_FLAGS_OFFSET` | `0x62` | **Omen Termal Profil Bayrakları Adresi:** Omen cihazlarında Turbo modunu etkinleştirmek (`0x04`) veya zamanlayıcıyı devre dışı bırakmak (`0x02`) için kullanılan özel bayrak hücresi. |
| `HP_OMEN_EC_THERMAL_PROFILE_TIMER_OFFSET` | `0x63` | **Omen Termal Profil Zamanlayıcı Adresi:** Omen Command Center tarafından yönetilen ve sıfıra ulaştığında profili otomatik olarak "Dengeli" moda sıfırlayan EC zamanlayıcı hücresi. |
| `HP_OMEN_EC_THERMAL_PROFILE_OFFSET` | `0x95` | **Klasik Omen Termal Profil Adresi:** Eski nesil Omen (V1 Legacy) ve bazı Victus modellerinde kullanılan klasik profil durumu kayıt adresi. |

---

## 3. Anakartlar (DMI Board) ve Ofset Eşleştirmeleri

`hp-wmi.c`, bilgisayarın anakart kimliğini (**DMI Board Name**) okuyarak hangi EC ofsetlerini ve termal parametreleri kullanacağını belirler.

### 3.1. Victus ve Omen Anakart Parametre Eşleştirme Tablosu

`victus_s_thermal_profile_boards` yapısında tanımlanan anakartlar, bunlara atanan termal profil parametreleri ve kullanılan EC ofsetleri aşağıda listelenmiştir:

| Anakart ID (DMI Board Name) | İlgili Bilgisayar Modeli / Serisi | Termal Parametre Grubu | EC Profil Ofseti | Performance Değeri | Balanced Değeri | Low Power Değeri | Açıklama / Özel Durumlar |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **8A13** | OMEN by HP Laptop 16-b1xxx | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Klasik Omen V1 düzenini kullanan anakart. |
| **8A4D** | HP Omen Serisi | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Klasik Omen V1 düzeni. |
| **8BAB** | HP Omen Serisi | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 ofsetini kullanan Omen anakartı. |
| **8BBE** | HP Victus Serisi | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Bilinmeyen EC (0x00). Yazılımsal platform profili takibi yapılır. |
| **8BCA** | HP Omen Serisi | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 ofseti. |
| **8BCD** | HP Omen Serisi | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 ofseti. |
| **8BD4** | HP Victus Serisi | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Bilinmeyen EC (0x00). |
| **8BD5** | HP Victus Serisi | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Bilinmeyen EC (0x00). |
| **8C76** | HP Omen Serisi | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 ofseti. |
| **8C77** | HP Omen Serisi | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Klasik 0x95 ofseti kullanan modern Omen. |
| **8C78** | HP Omen Serisi | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 ofseti. |
| **8E35** | HP Omen Serisi | `omen_v1_thermal_params` | `0x59` | `0x31` | `0x30` | `0x30` | Modern 0x59 ofseti. |
| **8C99** | HP Victus Serisi | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Bilinmeyen EC (0x00). |
| **8C9C** | HP Victus Serisi (örn: 16-s1034nf) | `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Bilinmeyen EC (0x00). Güç kaynağı değişiminde PL1/PL2 tetiklemesi gerektirir. |
| **8D41** | HP Omen Max (örn: 16-u0xxx) | `omen_v1_unknown_ec_thermal_params`| `0x00` | `0x31` | `0x30` | `0x30` | EC adresi bilinmeyen ama Omen V1 kodları kullanan anakart. |
| **8D87** | HP Omen Serisi | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | EC okuması tamamen devre dışı bırakılmış anakart. |
| **8BA9** | HP Omen Serisi | `omen_v1_legacy_thermal_params` | `0x95` | `0x31` | `0x30` | `0x30` | Klasik Omen V1 düzeni. |
| **8BAC** | HP Omen 16-wf0xxx | `omen_v1_no_ec_thermal_params` | `0x01` | `0x31` | `0x30` | `0x30` | **Kritik ACPI Hatası:** ACPI tablolarında GETB fonksiyonu bozuktur (sıfır uzunluklu alan oluşturma hatası). EC termal okumaları kilitlenmeyi önlemek için devre dışı bırakılmıştır. |
| **8BC2** | Victus by HP Gaming Laptop 16-r0xxx| `victus_s_thermal_params` | `0x00` | `0x01` | `0x00` | `0x00` | Bilinmeyen EC (0x00). |

---

### 3.2. Diğer Özel DMI Board Grupları

#### Omen Termal Profil Destekli Anakartlar (`omen_thermal_profile_boards`)
Aşağıdaki anakartlar, Windows Omen Command Center uygulamasının yetenek konfigürasyon dosyasından derlenmiştir. Bu anakartlar sürücü tarafından Omen termal profil yolları kullanılarak işlenir:
> `84DA`, `84DB`, `84DC`, `8572`, `8573`, `8574`, `8575`, `8600`, `8601`, `8602`, `8603`, `8604`, `8605`, `8606`, `8607`, `860A`, `8746`, `8747`, `8748`, `8749`, `874A`, `8786`, `8787`, `8788`, `878A`, `878B`, `878C`, `87B5`, `886B`, `886C`, `88C8`, `88CB`, `88D1`, `88D2`, `88F4`, `88F5`, `88F6`, `88F7`, `88FD`, `88FE`, `88FF`, `8900`, `8901`, `8902`, `8912`, `8917`, `8918`, `8949`, `894A`, `89EB`, `8A15`, `8A42`, `8BAD`, `8BAC`, `8C77`, `8D41`, `8E35`, `8E41`, `8BA9`

#### Omen V0 Moduna Zorlanan Anakartlar (`omen_thermal_profile_force_v0_boards`)
Bu anakartlar, BIOS'un döndürdüğü sistem tasarım bilgisine bakılmaksızın doğrudan eski nesil Omen V0 termal profillerini kullanmaya zorlanır:
> `8607`, `8746`, `8747`, `8748`, `8749`, `874A`

#### EC Zamanlayıcısına Sahip Omen Anakartlar (`omen_timed_thermal_profile_boards`)
Bu cihazlar, performans moduna alındığında EC üzerinde 120 saniyelik bir zamanlayıcı başlatır. Sürücü bu zamanlayıcıyı sıfırlayarak performans modunun sürekli kalmasını sağlar:
> `8A15`, `8A42`, `8BAD`

#### Victus 16-d Serisi Anakartlar (`victus_thermal_profile_boards`)
Victus serisinin ilk nesil termal profil kontrol şemasını kullanan modelleri:
> `88F8`, `8A25`

---

## 4. Termal Profiller ve Hex Karşılıkları

Linux `platform_profile` arayüzü, kullanıcıdan aldığı profilleri (Performance, Balanced vb.) sürücünün ve gömülü denetleyicinin (EC) anlayacağı hex kodlarına dönüştürür. HP cihazlarında bu modların karşılıkları nesillere ve serilere göre değişiklik gösterir.

### 4.1. Klasik / Standart HP Modları
`enum hp_thermal_profile` altındaki tanımlamalar:

| Profil İsmi | Hex Değeri | Linux Karşılığı | Açıklama |
| :--- | :---: | :--- | :--- |
| `HP_THERMAL_PROFILE_PERFORMANCE` | `0x00` | `performance` | Maksimum CPU/GPU gücü ve agresif fan eğrisi. |
| `HP_THERMAL_PROFILE_DEFAULT` | `0x01` | `balanced` | Standart günlük kullanım, dengeli güç ve gürültü. |
| `HP_THERMAL_PROFILE_COOL` | `0x02` | `cool` | Cihaz yüzey sıcaklığını düşük tutmak için azaltılmış güç sınırları. |
| `HP_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` | Minimum fan gürültüsü için düşük güç profili. |

### 4.2. HP Omen Serisi Modları

#### Omen V0 (Eski Nesil)
`enum hp_thermal_profile_omen_v0` altındaki tanımlamalar:

| Profil İsmi | Hex Değeri | Linux Karşılığı |
| :--- | :---: | :--- |
| `HP_OMEN_V0_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_OMEN_V0_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |
| `HP_OMEN_V0_THERMAL_PROFILE_COOL` | `0x02` | `cool` |

#### Omen V1 (Modern Nesil)
`enum hp_thermal_profile_omen_v1` altındaki tanımlamalar:

| Profil İsmi | Hex Değeri | Linux Karşılığı |
| :--- | :---: | :--- |
| `HP_OMEN_V1_THERMAL_PROFILE_DEFAULT` | `0x30` | `balanced` |
| `HP_OMEN_V1_THERMAL_PROFILE_PERFORMANCE`| `0x31` | `performance` |
| `HP_OMEN_V1_THERMAL_PROFILE_COOL` | `0x50` | `cool` |

### 4.3. HP Victus Serisi Modları

#### Standart Victus (16-d Serisi)
`enum hp_thermal_profile_victus` altındaki tanımlamalar:

| Profil İsmi | Hex Değeri | Linux Karşılığı |
| :--- | :---: | :--- |
| `HP_VICTUS_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` |
| `HP_VICTUS_THERMAL_PROFILE_PERFORMANCE` | `0x01` | `performance` |
| `HP_VICTUS_THERMAL_PROFILE_QUIET` | `0x03` | `quiet` |

#### Victus S-Serisi (16-r ve 16-s Serileri)
`enum hp_thermal_profile_victus_s` altındaki tanımlamalar:

| Profil İsmi | Hex Değeri | Linux Karşılığı |
| :--- | :---: | :--- |
| `HP_VICTUS_S_THERMAL_PROFILE_DEFAULT` | `0x00` | `balanced` veya `low_power` (ECO)* |
| `HP_VICTUS_S_THERMAL_PROFILE_PERFORMANCE`| `0x01` | `performance` |

> [!NOTE]
> *Victus S modellerinde hem `Balanced` hem de `Low Power` modları EC tarafında `0x00` değerine eşlenir. Sürücü, bu iki modu birbirinden ayırmak için GPU güç durumlarını (CTGP ve PPAB) sorgular. Eğer iki GPU özelliği de kapalıysa mod `low_power` (ECO) olarak, PPAB aktifse `balanced` olarak raporlanır.

---

## 5. Grafik ve Güç Limitleri Kontrolü (GPU & CPU PL1/PL2)

Modern Victus ve Omen dizüstü bilgisayarlarda termal profiller sadece fan hızlarını değil, doğrudan CPU ve GPU güç sınırlarını da (TGP/TDP) kontrol eder.

### 5.1. GPU Güç Yönetimi (cTGP ve PPAB)
Sürücü, GPU termal durumunu kontrol etmek için `HPWMI_SET_GPU_THERMAL_MODES_QUERY` (`0x22`) sorgusunu kullanır. `struct victus_gpu_power_modes` yapısı şu parametreleri içerir:

| Parametre | Tipi | İşlevi |
| :--- | :---: | :--- |
| `ctgp_enable` | `u8` | **Configurable TGP:** Ekran kartının en yüksek güç sınırına (örn: 80W yerine 120W) çıkmasını sağlar. `Performance` modunda `0x01` (aktif), diğer modlarda `0x00` değerini alır. |
| `ppab_enable` | `u8` | **Dynamic Boost (PPAB):** CPU ve GPU arasında yük durumuna göre dinamik güç paylaşımını yönetir. `Low Power` modunda `0x00` (kapalı), `Balanced` ve `Performance` modlarında `0x01` (açık) olur. |
| `dstate` | `u8` | **GPU Güç Durumu:** GPU'ya ayrılan güç önceliğini belirler (Sürücüde varsayılan olarak `1` yani %100 öncelik atanmıştır). |
| `gpu_slowdown_temp` | `u8` | **GPU Yavaşlama Sıcaklığı:** Ekran kartının termal kısmaya (thermal throttling) gireceği sıcaklık eşiğidir. BIOS'tan okunur ve üzerine yazılmadan korunur. |

### 5.2. CPU Güç Sınırları (PL1 ve PL2)
Victus S-serisi anakartlarda, `HPWMI_SET_POWER_LIMITS_QUERY` (`0x29`) komutuyla CPU'nun **PL1 (Uzun Süreli Güç Sınırı)** ve **PL2 (Kısa Süreli Güç Sınırı)** değerleri ayarlanır:
* `pl2` değeri her zaman `pl1` değerine eşit veya büyük olmak zorundadır (`pl2 >= pl1`).
* Güç kaynağı değişikliklerinde (AC adaptörün sökülüp takılması) performans modunun kilitlenmesini önlemek için sürücü otomatik olarak `victus_s_powersource_event` dinleyicisi üzerinden varsayılan sınırları (`HP_POWER_LIMIT_DEFAULT` -> `0x00`) yeniden uygular.

---

## 6. Gelişmiş Fan Denetimi (Hwmon Yapısı)

Sürücü, Linux donanım izleme alt yapısı (`hwmon`) aracılığıyla fan hızlarının izlenmesini ve manuel olarak ayarlanmasını sağlar.

### 6.1. Fan Denetim Modları
Fan kontrolü `enum pwm_modes` ile üç farklı modda çalışabilir:

| Mod İsmi | Değeri | Açıklama |
| :--- | :---: | :--- |
| `PWM_MODE_MAX` | `0` | **Maksimum Fan:** Fanlar en yüksek devirde (%100) çalışmaya zorlanır. |
| `PWM_MODE_MANUAL` | `1` | **Manuel Kontrol:** Kullanıcı fan devrini (RPM) doğrudan sysfs üzerinden el ile ayarlar. |
| `PWM_MODE_AUTO` | `2` | **Otomatik Kontrol:** Fan kontrolü tamamen Embedded Controller (EC) algoritmasına devredilir. |

### 6.2. Bekçi Zamanlayıcı (Keep-Alive Watchdog)
HP gömülü denetleyicisi (EC), manuel fan moduna veya maksimum fan moduna geçildiğinde donanımsal güvenlik amacıyla **120 saniyelik bir geri sayım zamanlayıcısı** başlatır. 120 saniye boyunca yeni bir WMI komutu gönderilmezse, EC otomatik olarak güvenlik nedeniyle manuel moddan çıkar ve fanları otomatik moda (`AUTO`) geri döndürür.

Bunu engellemek için sürücüde gecikmeli çalışan bir iş parçacığı (**Delayed Work - Keep Alive Watchdog**) kurgulanmıştır:
* Sürücü, **90 saniyede bir** (`KEEP_ALIVE_DELAY_SECS = 90`) arka planda sessizce donanıma mevcut fan modunu ve hızlarını yeniden gönderir.
* Böylece 120 saniyelik EC zamanlayıcısı donanım düzeyinde sürekli sıfırlanarak manuel kontrolün kalıcı olması sağlanır.
* Kullanıcı modu `AUTO` yaptığında ise bu zamanlayıcı iş parçacığı (`cancel_delayed_work_sync`) durdurulur ve denetim EC'ye bırakılır.

### 6.3. Victus S Fan Tablosu Yapısı
Victus S serisinde fan hız sınırları, BIOS'tan `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY` (`0x2F`) komutuyla okunan özel bir tabloya göre belirlenir. Bu tablonun veri yapısı:

```c
struct victus_s_fan_table_header {
    u8 unknown;
    u8 num_entries; // Tablodaki adım/satır sayısı
} __packed;

struct victus_s_fan_table_entry {
    u8 cpu_rpm;     // CPU fan hızı (değer * 100 RPM)
    u8 gpu_rpm;     // GPU fan hızı (değer * 100 RPM)
    u8 unknown;
} __packed;
```
* **Minimum Hız:** Tablonun ilk elemanından (`entries[0].cpu_rpm`) okunur.
* **Maksimum Hız:** Tablonun son elemanından (`entries[num_entries-1]`) okunur.
* **Fallback Mekanizması:** Eğer anakart fan tablosunu vermeyi desteklemiyorsa veya tablo bozuksa sürücü hata verip kapanmak yerine **5000 RPM** güvenli sınırı içeren varsayılan bir acil durum tablosunu (`setup_fallback_fan_limits`) devreye sokar.

---

## 7. WMI Olay Bildirimleri (Event IDs)

`HPWMI_EVENT_GUID` üzerinden dinlenen ACPI bildirim kodları ve sürücünün bu olaylara verdiği tepkiler:

| Olay Kodu (Hex) | Olay Adı (Sürücü Tanımı) | Gerçekleştiği Durum ve Sürücü Aksiyonu |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DOCK_EVENT` | Docking istasyonuna bağlanma/ayrılma veya tablet modu değişimi. Sürücü `input_report_switch` ile durumu sisteme bildirir. |
| `0x02` | `HPWMI_PARK_HDD` | Ani hareket sensörü tetiklendiğinde HDD kafasını park etme sinyali (Gelişmiş veri koruması). |
| `0x03` | `HPWMI_SMART_ADAPTER` | Orijinal olmayan veya yetersiz güç sunan şarj aleti uyarısı tetiklendiğinde çalışır. |
| `0x04` | `HPWMI_BEZEL_BUTTON` | Ekran çerçevesi üzerindeki özel tuşlara basıldığında klavye olayını raporlar. |
| `0x05` | `HPWMI_WIRELESS` | Kablosuz donanım durumunun (Wi-Fi, Bluetooth, WWAN) değiştiğini bildirir; rfkill durumlarını günceller. |
| `0x06` | `HPWMI_CPU_BATTERY_THROTTLE` | 3 hücreli pillerde aşırı deşarjı önlemek için CPU performans sınırlama bildirimi. |
| `0x0A` | `HPWMI_COOLSENSE_SYSTEM_MOBILE` | HP CoolSense teknolojisi: Cihazın kucakta olduğunu algılayıp yüzey sıcaklığını düşürür. |
| `0x0B` | `HPWMI_COOLSENSE_SYSTEM_HOT` | HP CoolSense teknolojisi: Cihazın masa üstünde olduğunu algılayıp tam performansa izin verir. |
| `0x0D` | `HPWMI_BACKLIT_KB_BRIGHTNESS` | Klavye arka aydınlatma seviyesi değiştiğinde tetiklenir. |
| `0x1A` | `HPWMI_CAMERA_TOGGLE` | **Kamera Perdesi Değişimi:** Fiziksel kamera anahtarı kapatıldığında veya açıldığında çalışır (`0xFF`: Kapalı, `0xFE`: Açık). |
| `0x1B` | `HPWMI_FN_P_HOTKEY` | **Fn + P Tuş Kombinasyonu:** Kullanıcı bu tuşlara bastığında termal profiller arasında döngüsel geçiş yapılır (`platform_profile_cycle`). |
| `0x1D` | `HPWMI_OMEN_KEY` | **Omen Tuşu:** Omen Gaming Hub'ı açan özel logolu tuş. Sisteme `KEY_PROG2` tuş kodu olarak iletimir. |

---

## 8. Sürücü WMI Komut ve Sorgu Kodları

Sürücünün BIOS ile gerçekleştirdiği tüm sorgularda (`hp_wmi_perform_query`) kullanılan komut ve sorgu türleri:

### 8.1. WMI Sorgu Kodları (`enum hp_wmi_commandtype`)
`hp_wmi_perform_query` fonksiyonunun ilk parametresi olan `query` alanına gönderilen hex değerleri:

| Hex Kod | Sorgu Adı (Makro) | Görevi |
| :---: | :--- | :--- |
| `0x01` | `HPWMI_DISPLAY_QUERY` | Ekran durumunu sorgulama. |
| `0x02` | `HPWMI_HDDTEMP_QUERY` | Sabit disk sıcaklık bilgisini alma. |
| `0x03` | `HPWMI_ALS_QUERY` | Ortam ışık sensörü (Ambient Light Sensor) kontrolü. |
| `0x04` | `HPWMI_HARDWARE_QUERY` | Docking istasyonu ve tablet modu durumunu sorgulama. |
| `0x05` | `HPWMI_WIRELESS_QUERY` | Klasik nesil kablosuz ağ anahtarı durumunu sorgulama/yazma. |
| `0x07` | `HPWMI_BATTERY_QUERY` | Pil sağlık ve doluluk bilgilerini alma. |
| `0x09` | `HPWMI_BIOS_QUERY` | BIOS özelliklerini sorgulama / Kısayolları aktifleştirme (`0x6E` yazarak). |
| `0x0B` | `HPWMI_FEATURE_QUERY` | BIOS'un 2008 ve sonrası özellik setlerini sorgulama. |
| `0x0C` | `HPWMI_HOTKEY_QUERY` | Basılan WMI özel kısayol tuşunun kodunu okuma. |
| `0x0D` | `HPWMI_FEATURE2_QUERY` | BIOS'un 2009 ve sonrası gelişmiş özellik setlerini sorgulama. |
| `0x1B` | `HPWMI_WIRELESS2_QUERY` | Modern nesil çoklu kablosuz cihaz (rfkill2) durumunu yönetme. |
| `0x2A` | `HPWMI_POSTCODEERROR_QUERY` | BIOS POST hata kodlarını okuma ve sıfırlama. |
| `0x40` | `HPWMI_SYSTEM_DEVICE_MODE` | Ekran kartı modu (Mux Switch) ve tablet modu tespiti / yönetimi. |
| `0x4C` | `HPWMI_THERMAL_PROFILE_QUERY` | Klasik termal profilleri okuma ve yazma. |

### 8.2. Gaming / Omen Özel Sorgu Kodları (`enum hp_wmi_gm_commandtype`)
Omen Command Center protokolünü taklit etmek için kullanılan oyun odaklı WMI sorguları:

| Hex Kod | Sorgu Adı (Makro) | Görevi |
| :---: | :--- | :--- |
| `0x10` | `HPWMI_FAN_COUNT_GET_QUERY` | Fan sayısını okur. Donanım düzeyinde "kullanıcı tanımlı fan modu" tetiği görevi görür. |
| `0x11` | `HPWMI_FAN_SPEED_GET_QUERY` | Klasik fan devrini okuma. |
| `0x1A` | `HPWMI_SET_PERFORMANCE_MODE` | Omen termal profilini EC'ye yazma. |
| `0x21` | `HPWMI_GET_GPU_THERMAL_MODES_QUERY`| GPU cTGP ve PPAB durumlarını okuma. |
| `0x22` | `HPWMI_SET_GPU_THERMAL_MODES_QUERY`| GPU cTGP ve PPAB güç sınırlarını yazma. |
| `0x26` | `HPWMI_FAN_SPEED_MAX_GET_QUERY` | Maksimum fan modunun aktif olup olmadığını sorgular. |
| `0x27` | `HPWMI_FAN_SPEED_MAX_SET_QUERY` | Maksimum fan modunu açar (`0x01`) veya kapatır (`0x00`). |
| `0x28` | `HPWMI_GET_SYSTEM_DESIGN_DATA` | Omen termal şema versiyonunu (V0 veya V1) okur. |
| `0x29` | `HPWMI_SET_POWER_LIMITS_QUERY` | CPU PL1 ve PL2 limitlerini yazar. |
| `0x2D` | `HPWMI_VICTUS_S_FAN_SPEED_GET_QUERY`| Victus S serisinde her iki fanın devrini eşzamanlı olarak okur. |
| `0x2E` | `HPWMI_VICTUS_S_FAN_SPEED_SET_QUERY`| Victus S serisinde fan hızlarını RPM olarak el ile ayarlar. |
| `0x2F` | `HPWMI_VICTUS_S_GET_FAN_TABLE_QUERY`| BIOS'tan anakarta gömülü fan hızı / RPM eşik tablosunu okur. |

---

## 9. Kritik Hata Çözümleri ve Yamalar (Fixes)

Sürücü içinde zamanla donanım uyumluluğu sağlamak adına eklenmiş bazı önemli yazılımsal yamalar ve önlemler bulunmaktadır:

### 1. NVIDIA Dynamic Boost DC Kilitlenme Çözümü (xcellsior yaması)
* **Sorun:** EC düzeni tam olarak çözülememiş anakartlarda (özellikle HP Omen Max 16, Board `8D41`), sürücü yüklenirken (probe aşamasında) yapılan zamansız bir WMI fan kontrolü yazması, ACPI tarafında Nvidia Dynamic Boost DC denetleyicisini devre dışı bırakıyordu. Bu durum ekran kartının en düşük TGP değerinde (örn: 80W) kilitlenmesine yol açıyordu.
* **Çözüm:** Sürücüye eklenen yama ile eğer anakartın EC ofseti bilinmiyorsa (`HP_EC_OFFSET_UNKNOWN`), sürücü başlangıçta donanıma hiçbir fan kontrol paketi göndermez. Fan durumunun eşitlenmesi kullanıcının ilk sysfs yazmasına kadar ertelenir, böylece GPU gücü kilitlenmez.

### 2. ACPI GETB Fonksiyon Hatası Engellemesi (Board 8BAC)
* **Sorun:** `8BAC` kodlu HP Omen 16-wf0xxx anakartlarında, ACPI DSDT tablosundaki `GETB` yardımcı fonksiyonunun içinde sıfır uzunluklu alan oluşturulmaya çalışılmaktadır. Bu ACPI hatası nedeniyle sürücünün attığı tüm WMI sorguları işletim sisteminin ACPI alt yapısını kilitleyip çökmelere sebep oluyordu.
* **Çözüm:** Bu anakart `omen_v1_no_ec_thermal_params` grubuna atanmıştır. Sürücü bu anakartı gördüğünde EC üzerinden termal profil okuma işlemlerini pas geçer ve sanal/önbelleğe alınmış değerleri kullanarak sistem kararlılığını korur.

### 3. Kamera Perdesi Desteği (`camera_shutter_input_setup`)
* **Sorun:** Fiziksel kamera gizlilik anahtarı olan modellerde, kamera kapatıldığında bunun kullanıcı arayüzüne bildirilmesi gerekiyordu.
* **Çözüm:** Sürücü başlangıçta sanal bir giriş cihazı oluşturur (`HP WMI camera shutter`). `0x1A` olay kodu tetiklendiğinde, perdenin kapalı (`0xFF`) veya açık (`0xFE`) olduğu algılanarak Linux çekirdeğine standart `SW_CAMERA_LENS_COVER` anahtar kodu gönderilir.
