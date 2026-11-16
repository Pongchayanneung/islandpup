<!-- NAME NOTE: "IslandPup" is an assumed product name. To rename, find-and-replace "IslandPup" in SHARING.md, docs/CHARACTER_PACKS.md, NOTICE.md and README.md. -->

# IslandPup: คู่มือสำหรับเพื่อน

IslandPup คือ fork ของ [Vorssaint](https://github.com/vorssaint/vorssaint-utils) (GPL-3.0-or-later) ที่เพิ่มน้องหมา border collie แบบ pixel art ไว้ใน Dynamic Island บน Mac น้องหมาเปลี่ยนท่าตามสิ่งที่ Mac กำลังทำอยู่ ส่วนที่เหลือของแอปคือ Vorssaint เดิม

ไม่ใช่แอปทางการของ Vorssaint และผู้พัฒนาเดิมไม่ได้รับรอง ดูรายละเอียดใน [NOTICE.md](NOTICE.md)

## น้องหมาทำอะไรได้

มี 15 ท่า เลือกตามสถานะของเครื่อง (ลำดับความสำคัญตามที่เขียนใน `NotchDogState.swift`):

| ท่า | เมื่อไหร่ |
|---|---|
| `lowbat` | แบตเหลือ 20% หรือต่ำกว่าและไม่ได้เสียบชาร์จ |
| `wake` | เครื่องเพิ่งตื่นจาก sleep หรือเพิ่งปลดล็อกหน้าจอ (สั้น ๆ) |
| `sleep` | ไม่แตะเมาส์หรือคีย์บอร์ด 2 นาทีขึ้นไป |
| `awake` | เหมือน `sleep` แต่เปิด Keep Awake อยู่ (ตาตื่น) |
| `hot` | เครื่องร้อนจน thermal state ถึง serious ขึ้นไป |
| `meeting` | มีแอปกำลังใช้ไมโครโฟน |
| `focus` | Timer ของ Island กำลังเดิน |
| `working` | มี process ของ Claude Code ใช้ CPU อยู่ |
| `music` | กำลังเล่นเพลง |
| `typing` | เพิ่งพิมพ์คีย์บอร์ดภายใน 1.5 วินาที |
| `walk` / `run` / `sprint` | ตาม CPU รวมของเครื่อง (ประมาณ 25% เริ่มวิ่ง, 50% เริ่ม sprint, มี hysteresis กันสลับถี่) |
| `latenight` | 23:00 ถึง 04:59 และไม่มีสถานะที่สำคัญกว่า |
| `charging` | กำลังชาร์จและไม่มีสถานะที่สำคัญกว่า |

น้องหมาอยู่ข้างสถานะอื่นของ Island ได้ (timer, downloads, AI agent, calendar, Keep Awake) โดย Island จะขยายออกข้างละช่องให้ ถ้าแถบเมนูบาร์มีที่ว่างพอ ตอนเล่นเพลง น้องหมาอยู่ที่เดิมและมีกราฟิกคลื่นเสียง (equalizer) อยู่อีกฝั่ง ชื่อเพลงจะขึ้นเฉพาะตอนเพลงเปลี่ยน

## ข้อจำกัดของการตรวจจับ (ตามที่โค้ดทำจริง)

- **Claude Code**: ดูจากชื่อและ path ของ process (`claude` หรือไฟล์ชื่อเลขเวอร์ชันที่อยู่ใต้ `/claude/versions/`) แล้วดู CPU ของ process นั้น ถ้า CPU ถึงประมาณ 5% จึงนับว่า working และค้างท่านี้อีกราว 3 วินาที ถ้า Claude Code รอ API อยู่โดยไม่ใช้ CPU น้องหมาอาจไม่ขึ้นท่า working
- **Meeting**: ใช้สถานะ "ไมโครโฟนกำลังถูกใช้" ของ macOS ไม่ได้ดูว่าเป็น Zoom, Meet หรือ Teams แอปไหนเปิดไมค์ก็ขึ้นท่า meeting
- **Music**: ต้องได้ชื่อเพลงจาก player ประเภท Music หรือ Spotify เสียงจาก QuickTime ถูกมองข้าม และเสียงจาก iPhone ไม่ถูกมองเห็น
- **Typing และ sleep**: ดูจากเวลาที่ผ่านไปตั้งแต่เหตุการณ์ keyboard หรือเมาส์ครั้งล่าสุดของ macOS โค้ดส่วนนี้ไม่ได้ขอ permission เอง
- ข้อมูลทั้งหมดในหัวข้อนี้มาจากการอ่านโค้ด ยังไม่ได้ทดสอบกับ Zoom, Teams หรือ player แต่ละตัวบนเครื่องจริง

## ติดตั้ง

ต้องใช้ macOS 14 ขึ้นไปบน Apple Silicon (ตาม README ของ Vorssaint) เลือกวิธีใดวิธีหนึ่ง

**วิธี 1: คำสั่งบรรทัดเดียว (ง่ายที่สุด)** เปิด Terminal แล้ววาง:

```sh
curl -fsSL https://raw.githubusercontent.com/Pongchayanneung/islandpup/main/install.sh | bash
```

สคริปต์จะโหลด zip จาก Release, ตรวจ sha256, ลงใน Applications และเปิดแอปให้ ไม่ใช้ sudo และไม่ติด Gatekeeper อ่านสคริปต์ก่อนได้ที่ [install.sh](install.sh) อัปเดตเวอร์ชันใหม่ใช้คำสั่งเดิมซ้ำ ลบแอปด้วยคำสั่งเดิมโดยเติม `-s -- --uninstall` ต่อท้าย `bash` (เก็บการตั้งค่าและ pack ตัวละครไว้)

**วิธี 2: Homebrew** (ถ้ามี Homebrew อยู่แล้ว):

```sh
brew tap Pongchayanneung/islandpup https://github.com/Pongchayanneung/islandpup
brew trust Pongchayanneung/islandpup
brew install --cask islandpup
```

**วิธี 3: โหลดเอง** โหลด `IslandPup.zip` จากหน้า [Releases](https://github.com/Pongchayanneung/islandpup/releases) แตก zip ลาก `IslandPup.app` ไปไว้ใน Applications แล้วทำตามหัวข้อถัดไป

## เปิดครั้งแรก (Gatekeeper)

หัวข้อนี้ใช้เฉพาะวิธี 3 (วิธี 1 และ 2 ข้ามขั้นนี้ให้แล้ว) แอปนี้ **ไม่ได้ notarize กับ Apple** (เซ็นแบบ ad-hoc) macOS จึงอาจขึ้นว่า "ไม่สามารถตรวจสอบได้" หรือ "ถูกบล็อก" ทำอย่างใดอย่างหนึ่ง:

**วิธี 1: คลิกขวา**
1. ใน Finder ไปที่ Applications คลิกขวา (หรือ Control + คลิก) ที่แอป เลือก **Open**
2. กด **Open** ในหน้าต่างที่ขึ้นมา
3. ถ้าไม่มีปุ่ม Open ให้ไปที่ System Settings > Privacy & Security เลื่อนลงไปหา "was blocked" แล้วกด **Open Anyway** (ต้องลองเปิดแอปก่อนหนึ่งครั้ง ปุ่มนี้ถึงจะโผล่)

**วิธี 2: Terminal**
```sh
xattr -dr com.apple.quarantine /Applications/IslandPup.app
```
แล้วเปิดแอปตามปกติ

## Permission ที่ macOS จะถามหรือไม่ถาม

ตัวตรวจจับของน้องหมา (`NotchDogState.swift`) อ่าน CPU, แบตเตอรี่, thermal state, เวลา idle ของ input, รายการ process และสถานะไมค์ของ CoreAudio ในโค้ดส่วนนี้ไม่พบการเรียกขอสิทธิ์ (ยังไม่ได้ทดสอบบนเครื่องที่ยังไม่เคยให้สิทธิ์ใคร) แต่ Island และฟีเจอร์รอบ ๆ ที่น้องหมาอาศัยอยู่ขอสิทธิ์ตามนี้ (จาก `FeatureCatalog.swift` และ `Info.plist`):

| ฟีเจอร์ | สิทธิ์ที่ถูกขอ |
|---|---|
| Dynamic Island เอง | Accessibility และ Automation (ใช้ควบคุมการเล่นของแอปเพลง) |
| กราฟิกคลื่นเสียงตอนเล่นเพลง | System Audio Recording (`NSAudioCaptureUsageDescription`) ถ้าไม่ให้ น้องหมายังทำงาน แต่คลื่นเสียงอาจไม่ขยับ |
| Calendar strip | Calendar |
| Downloads strip | Files and Folders (Downloads) |

สิทธิ์ Microphone ของแอปมีไว้สำหรับ screen recording ของ Vorssaint เท่านั้น (ตามข้อความใน `Info.plist`) ท่า meeting ไม่ต้องใช้สิทธิ์นี้ ถ้าไม่ได้ใช้ฟีเจอร์นั้นก็กดไม่อนุญาตได้

## สิ่งที่ build ที่แชร์นี้ใช้ไม่ได้

- **Fan control ถูกถอดออก** เพราะตัว helper ผูกกับ signing ของผู้พัฒนาเดิม ใช้ไม่ได้กับ build ที่เซ็นเอง
- **Permission อาจถูกรีเซ็ตเมื่อเปลี่ยนแอปเป็นเวอร์ชันใหม่** เพราะแอปเซ็นแบบ ad-hoc macOS มองว่าเป็นแอปคนละตัวเมื่อลายเซ็นเปลี่ยน ถ้าน้องหมาหรือ Island หยุดตอบสนองหลังอัปเดต ให้ไปที่ System Settings > Privacy & Security ลบรายการเก่าของแอป แล้วเพิ่มใหม่

(สองข้อนี้เขียนตามที่ตกลงกันไว้สำหรับ build ที่แชร์ ตอนเขียนเอกสารยังไม่ได้ตรวจ binary จริงว่าตัดอะไรออกไปบ้าง)

## เปิดใช้น้องหมา

1. เปิด Settings ของแอป (ไอคอนในเมนูบาร์)
2. ไปที่หน้า **Dynamic Island** แล้วเปิด Island ให้ทำงานก่อน (ถ้ายังปิด หน้า Companion จะมีปุ่มเปิดให้)
3. เลือกแท็บ **Companion** (แท็บอื่นคือ Layout, Content, Activity, Behavior)
4. เปิดสวิตช์ **Companion** ที่ด้านบนขวา
5. ที่ **Appearance > Style** เลือก **Dog**

ในแท็บเดียวกันยังเลือกได้ว่าอยู่ซ้ายหรือขวาของกล้อง (Side of the camera), ให้เดินผ่านเป็นระยะ (Appear now and then), ให้ตอบสนองต่อเหตุการณ์ (React to what happens) และซ่อนเมื่อไม่มีอะไรทำ (Hide when idle) ชื่อเมนูอ้างจากข้อความภาษาอังกฤษใน `NotchMascotStrings.swift`

ถ้าอยากเปลี่ยนตัวละคร ดู [docs/CHARACTER_PACKS.md](docs/CHARACTER_PACKS.md)

## ปิดแอป

คลิกไอคอนแอปในเมนูบาร์ แล้วเลือก **Quit** (ในโค้ดต้นฉบับข้อความคือ "Quit Vorssaint" ใน build นี้ชื่ออาจเปลี่ยนตามการ rebrand) ถ้าอยากให้น้องหมาหายไปแต่ยังใช้แอปอยู่ ให้ปิดสวิตช์ Companion หรือเปลี่ยน Style กลับเป็น Minimal

## ปัญหาที่พบบ่อย

- **น้องหมาไม่ขึ้น**: ตรวจว่า Island เปิดอยู่, Companion เปิดอยู่ และ Style เป็น Dog
- **น้องหมาเดินท่าเดียว**: ท่าส่วนใหญ่ต้องมีสถานะที่ตรงเงื่อนไขในตารางข้างบน ถ้าไม่มี น้องหมาจะอยู่ที่ walk, run หรือ sprint ตาม CPU
- **ไม่ขึ้นท่า music**: ตรวจว่า player ส่งชื่อเพลงออกมา (Music, Spotify) และกำลัง play อยู่ ไฟล์เสียงใน QuickTime ไม่นับ
- ปัญหาทั่วไปของแอป ดู [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) และ [docs/PERMISSIONS.md](docs/PERMISSIONS.md) ของ Vorssaint
