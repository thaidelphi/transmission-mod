{******************************************************************************
 * ยูนิต: uTypes.pas
 * คำอธิบาย:
 *   รวบรวมค่าคงที่ (Constants), โครงสร้างข้อมูล (Records), คลาสโมเดลทอร์เรนต์ (TTorrentItem)
 *   และฟังก์ชันช่วยเหลือสำหรับการแปลงหน่วยแสดงผล (ขนาดไฟล์, ความเร็ว, Ratio, เวลา ETA)
 *   โดยอ้างอิงโครงสร้างข้อมูลตามมาตรฐาน Transmission JSON-RPC Specification
 ******************************************************************************}
unit uTypes;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, IniFiles, fpjson, jsonparser, base64, zstream{$IFDEF WINDOWS}, Registry, Windows{$ENDIF};

const
  { ค่าคงที่สถานะของทอร์เรนต์ (ตรงกับ enum tr_torrent_activity ใน libtransmission) }
  TR_STATUS_STOPPED       = 0; // หยุดทำงานชั่วคราว (Paused) หรือโหลดเสร็จและหยุดปล่อยแล้ว (Finished)
  TR_STATUS_CHECK_WAIT    = 1; // เข้าคิวรอตรวจสอบความถูกต้องของข้อมูลในดิสก์ (Queued for verification)
  TR_STATUS_CHECK         = 2; // กำลังตรวจสอบค่า SHA-1 Hash ของชิ้นส่วนไฟล์ (Verifying local data)
  TR_STATUS_DOWNLOAD_WAIT = 3; // เข้าคิวรอดาวน์โหลด (Queued for download)
  TR_STATUS_DOWNLOAD      = 4; // กำลังดาวน์โหลดข้อมูลจาก Peers (Downloading)
  TR_STATUS_SEED_WAIT     = 5; // เข้าคิวรอปล่อยไฟล์ (Queued for seeding)
  TR_STATUS_SEED          = 6; // กำลังปล่อยไฟล์ให้ผู้ใช้อื่น (Seeding)

  { ค่าคงที่ระดับความสำคัญของแบนด์วิดท์และไฟล์ (ตรงกับ tr_priority_t) }
  TR_PRI_LOW    = -1; // ความสำคัญต่ำ (Low Priority)
  TR_PRI_NORMAL =  0; // ความสำคัญปกติ (Normal Priority)
  TR_PRI_HIGH   =  1; // ความสำคัญสูง (High Priority)

  { ค่าคงที่โหมดการจำกัดอัตราส่วนการปล่อยไฟล์ (Seed Ratio Mode) }
  TR_RATIOLIMIT_GLOBAL    = 0; // ใช้ค่าตามที่ตั้งไว้ในระดับเซสชันหลัก (Use global settings)
  TR_RATIOLIMIT_SINGLE    = 1; // กำหนดค่า Ratio เฉพาะทอร์เรนต์นี้ (Stop seeding at torrent ratio)
  TR_RATIOLIMIT_UNLIMITED = 2; // ปล่อยไฟล์ไปเรื่อย ๆ โดยไม่สนใจ Ratio (Seed regardless of ratio)

  { รหัสยืนยันข้อความ WM_COPYDATA สำหรับการส่งต่ออาร์กิวเมนต์ระหว่างอินสแตนซ์ }
  SINGLE_INSTANCE_COPYDATA_ID = $54524C5A; // 'TRLZ'

type
  { โครงสร้างเก็บข้อมูลไฟล์ย่อยแต่ละไฟล์ภายในทอร์เรนต์ }
  TTorrentFileItem = record
    Index: Integer;          // ลำดับดัชนีของไฟล์ในทอร์เรนต์ (0..N-1) ใช้ส่งคำสั่ง files-wanted/unwanted
    Name: string;            // พาธและชื่อไฟล์ภายในทอร์เรนต์
    Length: Int64;           // ขนาดไฟล์ทั้งหมด (หน่วยเป็น Bytes)
    BytesCompleted: Int64;   // จำนวน Bytes ที่ดาวน์โหลดเสร็จแล้วของไฟล์นี้
    Wanted: Boolean;         // สถานะว่าต้องการดาวน์โหลดไฟล์นี้หรือไม่ (True = โหลด, False = ข้าม)
    Priority: Integer;       // ระดับความสำคัญของไฟล์ (TR_PRI_LOW / NORMAL / HIGH)
  end;

  { โครงสร้างเก็บข้อมูลของ Peer แต่ละรายที่กำลังเชื่อมต่ออยู่กับทอร์เรนต์ }
  TTorrentPeerItem = record
    Address: string;         // หมายเลข IP Address ของ Peer (IPv4 หรือ IPv6)
    Port: Integer;           // พอร์ตที่เชื่อมต่อของ Peer
    ClientName: string;      // ชื่อโปรแกรมบิตทอร์เรนต์ของฝั่ง Peer (เช่น Transmission 4.2.0, qBittorrent)
    FlagStr: string;         // รหัสสถานะการเชื่อมต่อ (เช่น D=Downloading, U=Uploading, E=Encrypted, T=uTP)
    Progress: Double;        // ความคืบหน้าของไฟล์ฝั่ง Peer (0.0 ถึง 1.0)
    RateToClient: Int64;     // ความเร็วที่เราดาวน์โหลดจาก Peer นี้ (Bytes/sec)
    RateToPeer: Int64;       // ความเร็วที่เราอัปโหลดให้ Peer นี้ (Bytes/sec)
    IsEncrypted: Boolean;    // เชื่อมต่อแบบเข้ารหัสโปรโตคอล (MSE/PE) หรือไม่
    IsUTP: Boolean;          // เชื่อมต่อผ่านโปรโตคอล µTP หรือไม่
  end;

  { โครงสร้างเก็บข้อมูลและสถิติของ Tracker แต่ละตัวในทอร์เรนต์ }
  TTorrentTrackerItem = record
    Id: Integer;                    // รหัสอ้างอิง Tracker ในเซสชัน (ใช้ตอนสั่งลบ/แก้ไข)
    Tier: Integer;                  // ลำดับกลุ่มของ Tracker (Tier 0 = หลัก, Tier 1+ = สำรอง)
    Announce: string;               // URL สำหรับ Announce ไปยัง Tracker
    Host: string;                   // ชื่อโดเมนหลักที่สกัดจาก Announce URL (ใช้กรองในแถบ Filter Bar)
    LastAnnounceResult: string;     // ข้อความผลลัพธ์จากการติดต่อ Tracker ครั้งล่าสุด (เช่น "Success")
    LastAnnounceTime: Int64;        // เวลาที่ติดต่อ Tracker ครั้งล่าสุด (Unix Timestamp)
    LastAnnounceSucceeded: Boolean; // สถานะว่าการติดต่อครั้งล่าสุดสำเร็จหรือไม่
    SeederCount: Integer;           // จำนวนผู้ปล่อยไฟล์ (Seeders) ที่ Tracker รายงาน (-1 = ไม่ทราบ)
    LeecherCount: Integer;          // จำนวนผู้ดาวน์โหลด (Leechers) ที่ Tracker รายงาน (-1 = ไม่ทราบ)
    DownloadCount: Integer;         // จำนวนครั้งที่ถูกดาวน์โหลดเสร็จสิ้นบน Tracker
  end;

  { TTorrentItem: คลาสแทนข้อมูลของทอร์เรนต์ 1 รายการ พร้อมฟังก์ชันคำนวณสถานะแสดงผล }
  TTorrentItem = class
  public
    Id: Integer;                      // รหัสอ้างอิงทอร์เรนต์ในเซสชัน RPC
    Name: string;                     // ชื่อทอร์เรนต์
    HashString: string;               // ค่า Info Hash (SHA-1 40 ตัวอักษรฐานสิบหก)
    Status: Integer;                  // สถานะปัจจุบัน (TR_STATUS_*)
    PercentDone: Double;              // เปอร์เซ็นต์ความคืบหน้าของไฟล์ที่เลือกดาวน์โหลด (0.0 ถึง 1.0)
    MetadataPercentComplete: Double;  // เปอร์เซ็นต์การดึงข้อมูลเมตาจากลิงก์ Magnet (0.0 ถึง 1.0)
    TotalSize: Int64;                 // ขนาดรวมของทุกไฟล์ในทอร์เรนต์ (Bytes)
    SizeWhenDone: Int64;              // ขนาดรวมเฉพาะไฟล์ที่ติ๊กเลือกดาวน์โหลด (Bytes)
    LeftUntilDone: Int64;             // จำนวน Bytes ที่ยังเหลือต้องดาวน์โหลดให้ครบ
    HaveValid: Int64;                 // จำนวน Bytes ที่ดาวน์โหลดและตรวจ Hash ผ่านแล้ว
    HaveUnchecked: Int64;             // จำนวน Bytes ที่ดาวน์โหลดมาแล้วแต่ยังไม่ได้ตรวจ Hash
    RateDownload: Int64;              // ความเร็วดาวน์โหลดปัจจุบัน (Bytes/sec)
    RateUpload: Int64;                // ความเร็วอัปโหลดปัจจุบัน (Bytes/sec)
    UploadRatio: Double;              // อัตราส่วนการอัปโหลดต่อดาวน์โหลด (Ratio)
    UploadedEver: Int64;              // ยอดอัปโหลดสะสมทั้งหมดของทอร์เรนต์นี้ (Bytes)
    DownloadedEver: Int64;            // ยอดดาวน์โหลดสะสมทั้งหมดของทอร์เรนต์นี้ (Bytes)
    ETA: Int64;                       // เวลาที่คาดว่าจะเสร็จเป็นวินาที (-1 = เสร็จแล้ว, -2 = ไม่ทราบ)
    PeersConnected: Integer;          // จำนวน Peers ที่เชื่อมต่ออยู่ทั้งหมด
    PeersSendingToUs: Integer;        // จำนวน Peers ที่กำลังส่งข้อมูลให้เรา
    PeersGettingFromUs: Integer;      // จำนวน Peers ที่กำลังรับข้อมูลจากเรา
    Error: Integer;                   // รหัสข้อผิดพลาด (0 = ปกติ, 1..3 = มีคำเตือนหรือข้อผิดพลาด)
    ErrorString: string;              // ข้อความอธิบายข้อผิดพลาดจาก Tracker หรือระบบดิสก์
    AddedDate: Int64;                 // วันที่เพิ่มทอร์เรนต์เข้าโปรแกรม (Unix Timestamp)
    DoneDate: Int64;                  // วันที่ดาวน์โหลดเสร็จสมบูรณ์ (Unix Timestamp)
    ActivityDate: Int64;              // เวลาที่มีการรับ-ส่งข้อมูลครั้งล่าสุด (Unix Timestamp)
    SecondsDownloading: Int64;        // เวลาสะสมที่ใช้ในการดาวน์โหลด (วินาที)
    SecondsSeeding: Int64;            // เวลาสะสมที่ใช้ในการปล่อยไฟล์ (วินาที)
    DownloadDir: string;              // โฟลเดอร์ปลายทางที่บันทึกไฟล์ของทอร์เรนต์นี้
    IsPrivate: Boolean;               // เป็นทอร์เรนต์ส่วนตัว (ปิด DHT/PEX) หรือไม่
    IsFinished: Boolean;              // โหลดครบและปล่อยครบตามเป้าหมาย Ratio แล้วหรือไม่
    Creator: string;                  // ชื่อโปรแกรมหรือผู้สร้างไฟล์ .torrent
    Comment: string;                  // ข้อความหมายเหตุแนบท้ายในไฟล์ .torrent
    PieceCount: Integer;              // จำนวนชิ้นส่วน (Pieces) ทั้งหมดของทอร์เรนต์
    PieceSize: Int64;                 // ขนาดของแต่ละ Piece (Bytes)
    QueuePosition: Integer;           // ลำดับคิวของทอร์เรนต์
    BandwidthPriority: Integer;       // ความสำคัญของแบนด์วิดท์ (TR_PRI_*)
    HonorsSessionLimits: Boolean;     // ใช้ข้อจำกัดความเร็วรวมของเซสชันหรือไม่
    DownloadLimited: Boolean;         // เปิดการจำกัดความเร็วดาวน์โหลดเฉพาะทอร์เรนต์นี้หรือไม่
    DownloadLimit: Int64;             // เพดานความเร็วดาวน์โหลดเฉพาะทอร์เรนต์นี้ (KB/s)
    UploadLimited: Boolean;           // เปิดการจำกัดความเร็วอัปโหลดเฉพาะทอร์เรนต์นี้หรือไม่
    UploadLimit: Int64;               // เพดานความเร็วอัปโหลดเฉพาะทอร์เรนต์นี้ (KB/s)
    SeedRatioMode: Integer;           // โหมดจำกัดการปล่อยไฟล์ (TR_RATIOLIMIT_*)
    SeedRatioLimit: Double;           // ค่า Ratio เป้าหมายเฉพาะทอร์เรนต์นี้
    SeedIdleMode: Integer;            // โหมดหยุดปล่อยเมื่อไม่มีความเคลื่อนไหว
    SeedIdleLimit: Integer;           // เวลาไม่มีความเคลื่อนไหวสูงสุดก่อนหยุดปล่อย (นาที)
    PeerLimit: Integer;               // จำนวน Peers สูงสุดที่อนุญาตให้เชื่อมต่อกับทอร์เรนต์นี้
    PrimaryTrackerHost: string;       // ชื่อโดเมนของ Tracker ตัวแรก (ใช้สำหรับตัวกรอง Tracker)
    MagnetLink: string;               // ลิงก์ Magnet (`magnet:?xt=urn:btih:...`)
    TrackerPaused: Boolean;           // ปิดการส่ง Packet ไปหา Tracker เฉพาะทอร์เรนต์นี้หรือไม่
    TrackerAutoPause: Boolean;        // ดึง Peer รอบแรกแล้วหยุดส่ง Packet Tracker อัตโนมัติหรือไม่
    Selected: Boolean;                // สถานะการถูกคลิกเลือกในตาราง UI

    Files: array of TTorrentFileItem;       // รายการไฟล์ย่อย (โหลดเมื่อเปิดหน้าต่าง Properties)
    Peers: array of TTorrentPeerItem;       // รายการ Peers (โหลดเมื่อเปิดหน้าต่าง Properties)
    Trackers: array of TTorrentTrackerItem; // รายการ Trackers

    { ฟังก์ชันตรวจสอบสถานะของทอร์เรนต์ }
    function IsPaused: Boolean;
    function IsDownloading: Boolean;
    function IsSeeding: Boolean;
    function IsVerifying: Boolean;
    function IsQueued: Boolean;
    function IsActive: Boolean;
    function HasError: Boolean;
    function HaveTotal: Int64;
    function EffectiveSeedRatioLimit(const GlobalRatioLimited: Boolean; const GlobalRatioLimit: Double): Double;

    { ฟังก์ชันสร้างข้อความสถานะสำหรับแสดงในโหมด Compact View และ Full View (เลียนแบบ TorrentDelegate ของ Qt) }
    function ShortStatusString: string;
    function FullStatusString: string;
    function ProgressSummaryString(const GlobalRatioLimited: Boolean; const GlobalRatioLimit: Double): string;
  end;

  { โครงสร้างเก็บการตั้งค่าระดับเซสชัน (ตรงกับผลลัพธ์ของคำสั่ง RPC `session-get`) }
  TSessionConfig = record
    Version: string;                    // เวอร์ชันของ Transmission Engine (เช่น "4.2.0-dev")
    RpcVersion: Integer;                // เวอร์ชันของโปรโตคอล RPC
    DownloadDir: string;                // โฟลเดอร์ดาวน์โหลดเริ่มต้น
    IncompleteDir: string;              // โฟลเดอร์พักไฟล์ที่ยังดาวน์โหลดไม่เสร็จ
    IncompleteDirEnabled: Boolean;      // เปิดใช้งานโฟลเดอร์พักไฟล์หรือไม่
    RenamePartialFiles: Boolean;        // เติมนามสกุล `.part` ต่อท้ายไฟล์ที่ยังโหลดไม่เสร็จหรือไม่
    StartAddedTorrents: Boolean;        // เริ่มดาวน์โหลดทันทีเมื่อเพิ่มทอร์เรนต์ใหม่หรือไม่
    TrashOriginalTorrentFiles: Boolean; // ลบไฟล์ `.torrent` ต้นฉบับหลังแอดเข้าโปรแกรมหรือไม่
    SpeedLimitDown: Int64;              // เพดานความเร็วดาวน์โหลดปกติ (KB/s)
    SpeedLimitDownEnabled: Boolean;     // เปิดจำกัดความเร็วดาวน์โหลดปกติหรือไม่
    SpeedLimitUp: Int64;                // เพดานความเร็วอัปโหลดปกติ (KB/s)
    SpeedLimitUpEnabled: Boolean;       // เปิดจำกัดความเร็วอัปโหลดปกติหรือไม่
    AltSpeedDown: Int64;                // เพดานความเร็วดาวน์โหลดในโหมดเต่า Turtle Mode (KB/s)
    AltSpeedUp: Int64;                  // เพดานความเร็วอัปโหลดในโหมดเต่า Turtle Mode (KB/s)
    AltSpeedEnabled: Boolean;           // เปิดใช้งานโหมดเต่า (Turtle Mode) อยู่หรือไม่
    AltSpeedTimeEnabled: Boolean;       // เปิดตั้งเวลาเปิด-ปิดโหมดเต่าอัตโนมัติหรือไม่
    AltSpeedTimeBegin: Integer;         // เวลาเริ่มโหมดเต่า (นาทีนับจากเที่ยงคืน)
    AltSpeedTimeEnd: Integer;           // เวลาสิ้นสุดโหมดเต่า (นาทีนับจากเที่ยงคืน)
    SeedRatioLimited: Boolean;          // เปิดจำกัดการปล่อยไฟล์เมื่อถึงค่า Ratio หรือไม่
    SeedRatioLimit: Double;             // ค่า Ratio เป้าหมายระดับเซสชัน (เช่น 2.0)
    IdleSeedingLimited: Boolean;        // เปิดหยุดปล่อยไฟล์เมื่อไม่มีผู้รับนานเกินเวลาหรือไม่
    IdleSeedingLimit: Integer;          // จำนวนนาทีที่ไม่มีผู้รับก่อนหยุดปล่อย
    Encryption: string;                 // โหมดการเข้ารหัส ('tolerated', 'preferred', 'required')
    PexEnabled: Boolean;                // เปิดใช้งาน Peer Exchange (PEX) หรือไม่
    DhtEnabled: Boolean;                // เปิดใช้งาน Distributed Hash Table (DHT) หรือไม่
    LpdEnabled: Boolean;                // เปิดใช้งาน Local Peer Discovery (LPD) หรือไม่
    UtpEnabled: Boolean;                // เปิดใช้งานโปรโตคอล µTP หรือไม่
    BlocklistEnabled: Boolean;          // เปิดใช้งาน IP Blocklist หรือไม่
    BlocklistUrl: string;               // URL สำหรับดาวน์โหลดรายการ Blocklist
    BlocklistSize: Integer;             // จำนวนกฎ IP ใน Blocklist ปัจจุบัน
    PeerPort: Integer;                  // พอร์ตหลักสำหรับรับการเชื่อมต่อจาก Peers (เช่น 51413)
    PeerPortRandomOnStart: Boolean;     // สุ่มพอร์ตใหม่ทุกครั้งที่เปิดโปรแกรมหรือไม่
    PortForwardingEnabled: Boolean;     // เปิดพอร์ตเร้าเตอร์อัตโนมัติด้วย UPnP/NAT-PMP หรือไม่
    PeerLimitGlobal: Integer;           // จำนวน Peers สูงสุดรวมทั้งโปรแกรม
    PeerLimitPerTorrent: Integer;       // จำนวน Peers สูงสุดต่อ 1 ทอร์เรนต์
    DownloadQueueEnabled: Boolean;      // เปิดจำกัดจำนวนคิวดาวน์โหลดพร้อมกันหรือไม่
    DownloadQueueSize: Integer;         // จำนวนทอร์เรนต์ที่ดาวน์โหลดพร้อมกันได้สูงสุด
    SeedQueueEnabled: Boolean;          // เปิดจำกัดจำนวนคิวปล่อยไฟล์พร้อมกันหรือไม่
    SeedQueueSize: Integer;             // จำนวนทอร์เรนต์ที่ปล่อยไฟล์พร้อมกันได้สูงสุด
    TrackerPaused: Boolean;             // ปิดการส่ง Packet ไปหา Tracker ทั้งโปรแกรมหรือไม่
    TrackerAutoPause: Boolean;          // ดึง Peer รอบแรกแล้วหยุดส่ง Packet Tracker อัตโนมัติ (ทั้งโปรแกรม)
    SupportsTrackerPause: Boolean;      // Daemon รองรับฟิลด์ tracker_paused และ ht..tps:// หรือไม่
    CacheSizeMiB: Integer;              // ขนาด RAM Cache สำหรับเขียน/อ่านดิสก์ (MiB)
  end;

  { การตั้งค่าพฤติกรรมฝั่งเดสก์ท็อป (บันทึกลง INI คล้ายตัวเลือกของ BitComet) }
  TDesktopPrefs = record
    MinimizeToTray: Boolean;         // เมื่อกดปุ่ม X ให้ย่อไปไว้มุมขวาล่างแทนปิดโปรแกรม
    PreventSleepWhenActive: Boolean; // ป้องกัน Windows เข้าโหมดหลับขณะกำลังดาวน์โหลด/ปล่อยไฟล์
    PlaySoundOnFinish: Boolean;      // เล่นเสียงแจ้งเตือนเมื่อดาวน์โหลดเสร็จ
    ShowNotifyOnFinish: Boolean;     // แสดงแถบแจ้งเตือนมุมขวาล่างเมื่อดาวน์โหลดเสร็จ
    WatchDirEnabled: Boolean;        // เปิดใช้งาน Watch Folder ดูไฟล์ .torrent อัตโนมัติ
    WatchDir: string;                // พาธของ Watch Folder
    WatchDirDeleteOriginal: Boolean; // ลบไฟล์ .torrent ต้นฉบับหลังแอด (False = เปลี่ยนเป็น .added)
    DataDir: string;                 // โฟลเดอร์เก็บประวัติและข้อมูล .torrent/.resume ถาวร (รองรับย้ายจาก C:\ เพื่อกันล้างเครื่อง)
  end;

  { รายการประวัติการดาวน์โหลดถาวร (เก็บไว้แม้ลบออกจากรายการหลักหรือล้าง Windows ใหม่) }
  THistoryItem = class
  public
    HashString: string;
    Name: string;
    TotalSize: Int64;
    DownloadedEver: Int64;
    UploadedEver: Int64;
    UploadRatio: Double;
    DownloadDir: string;
    MagnetLink: string;
    AddedDate: Int64;
    DoneDate: Int64;
    LastSeenDate: Int64;
    Completed: Boolean;
  end;

  { ตัวจัดการประวัติการดาวน์โหลดถาวร (download_history.json) และการสำรอง/กู้คืนข้อมูล (.trbak) }
  TDownloadHistoryManager = class
  private
    FItems: TList;
    FDirty: Boolean;
    function FindByHash(const HashStr: string): THistoryItem;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    function GetItem(Idx: Integer): THistoryItem;
    function LoadFromFile(const FilePath: string): Boolean;
    function SaveToFile(const FilePath: string): Boolean;
    function SyncFromTorrents(Torrents: TList; const FilePath: string; ForceSave: Boolean = False): Boolean;
    procedure RemoveByHash(const HashStr: string);
    property Dirty: Boolean read FDirty;
  end;

  { โครงสร้างเก็บข้อมูลสถิติของโปรแกรม (ตรงกับผลลัพธ์ของคำสั่ง RPC `session-stats`) }
  TSessionStatsData = record
    ActiveTorrentCount: Integer;    // จำนวนทอร์เรนต์ที่กำลังทำงานอยู่
    PausedTorrentCount: Integer;    // จำนวนทอร์เรนต์ที่หยุดชั่วคราว
    TorrentCount: Integer;          // จำนวนทอร์เรนต์ทั้งหมด
    DownloadSpeed: Int64;           // ความเร็วดาวน์โหลดรวมทุกทอร์เรนต์ขณะนี้ (Bytes/sec)
    UploadSpeed: Int64;             // ความเร็วอัปโหลดรวมทุกทอร์เรนต์ขณะนี้ (Bytes/sec)
    CurrentUploadedBytes: Int64;    // ยอดอัปโหลดในเซสชันปัจจุบัน (Bytes)
    CurrentDownloadedBytes: Int64;  // ยอดดาวน์โหลดในเซสชันปัจจุบัน (Bytes)
    CurrentFilesAdded: Integer;     // จำนวนไฟล์ที่เพิ่มในเซสชันปัจจุบัน
    CurrentSessionCount: Integer;   // จำนวนครั้งในเซสชันนี้
    CurrentSecondsActive: Int64;    // เวลาที่เปิดใช้งานในเซสชันปัจจุบัน (วินาที)
    TotalUploadedBytes: Int64;      // ยอดอัปโหลดสะสมทั้งหมดตั้งแต่เริ่มใช้โปรแกรม (Bytes)
    TotalDownloadedBytes: Int64;    // ยอดดาวน์โหลดสะสมทั้งหมดตั้งแต่เริ่มใช้โปรแกรม (Bytes)
    TotalFilesAdded: Integer;       // จำนวนไฟล์ที่เพิ่มสะสมทั้งหมด
    TotalSessionCount: Integer;     // จำนวนครั้งที่เปิดใช้งานสะสมทั้งหมด
    TotalSecondsActive: Int64;      // เวลาที่เปิดใช้งานสะสมทั้งหมด (วินาที)
  end;

{ ฟังก์ชันแปลงตัวเลขเป็นข้อความที่มนุษย์อ่านง่าย (Human-readable formatters) }
function FormatSize(Bytes: Int64): string;
function FormatSpeed(BytesPerSec: Int64): string;
function FormatRatio(Ratio: Double): string;
function FormatETA(Seconds: Int64): string;
function FormatDuration(Seconds: Int64): string;
function FormatPercent(Frac: Double): string;
function ExtractTrackerHost(const AnnounceUrl: string): string;
function HasCliFlag(const Flag: string): Boolean;
function GetWindowsAutoStart(out StartMinimized: Boolean): Boolean;
function SetWindowsAutoStart(Enabled, StartMinimized: Boolean): Boolean;
function GetTorrentFileAssociation: Boolean;
function SetTorrentFileAssociation(Enabled: Boolean): Boolean;
function GetMagnetProtocolAssociation: Boolean;
function SetMagnetProtocolAssociation(Enabled: Boolean): Boolean;
function GetDefaultPortableDataDir: string;
function GetEmbeddedBinDir(const PreferredDataDir: string): string;
function LoadDestinationDirHistory(OutDirs: TStrings; const FallbackDefaultDir: string): string;
procedure SaveDestinationDirToHistory(const DirPath: string);
function EnsureEmbeddedAsset(const ResName, TargetFilePath: string): Boolean;
function ExportPortableBackup(const DestFilePath, DataDir, IniPath: string;
  History: TDownloadHistoryManager): Boolean;
function ImportPortableBackup(const SrcFilePath, DataDir: string;
  History: TDownloadHistoryManager; out RestoredFiles: Integer): Boolean;
procedure SetPreventSystemSleep(Active: Boolean);
procedure PlayCompletionSound;
type
  TSingleInstancePayloadEvent = procedure(const Payload: string) of object;

function AcquireSingleInstanceLock: Boolean;
procedure ReleaseSingleInstanceLock;
procedure RegisterMainWindowForSingleInstance(MainHwnd: PtrUInt; OnPayload: TSingleInstancePayloadEvent = nil);
procedure UnregisterSingleInstanceWindow;
procedure NotifyExistingInstance;
procedure ForceForegroundHwnd(HwndVal: PtrUInt);

implementation

{ แปลงจำนวน Bytes เป็นหน่วย B, KB, MB, GB, TB อัตโนมัติ }
function FormatSize(Bytes: Int64): string;
const
  Units: array[0..4] of string = ('B', 'KB', 'MB', 'GB', 'TB');
var
  Val: Double;
  Idx: Integer;
begin
  if Bytes <= 0 then
    Exit('0 B');
  Val := Bytes;
  Idx := 0;
  while (Val >= 1024.0) and (Idx < High(Units)) do
  begin
    Val := Val / 1024.0;
    Inc(Idx);
  end;
  if Idx = 0 then
    Result := Format('%d %s', [Bytes, Units[Idx]])
  else if Val < 10.0 then
    Result := Format('%.2f %s', [Val, Units[Idx]])
  else if Val < 100.0 then
    Result := Format('%.1f %s', [Val, Units[Idx]])
  else
    Result := Format('%.0f %s', [Val, Units[Idx]]);
end;

{ แปลงความเร็ว Bytes/sec เป็นข้อความ เช่น "1.25 MB/s" }
function FormatSpeed(BytesPerSec: Int64): string;
begin
  if BytesPerSec <= 0 then
    Result := '0 B/s'
  else
    Result := FormatSize(BytesPerSec) + '/s';
end;

{ แปลงค่า Ratio เป็นทศนิยม 2 ตำแหน่ง }
function FormatRatio(Ratio: Double): string;
begin
  if Ratio < 0 then
    Result := 'None'
  else if IsInfinite(Ratio) or IsNan(Ratio) then
    Result := 'Inf'
  else if Ratio < 10.0 then
    Result := Format('%.2f', [Ratio])
  else if Ratio < 100.0 then
    Result := Format('%.1f', [Ratio])
  else
    Result := Format('%.0f', [Ratio]);
end;

{ แปลงค่า ETA (วินาที) เป็นข้อความเวลาที่เหลือ }
function FormatETA(Seconds: Int64): string;
begin
  if Seconds = -1 then
    Result := 'Done'
  else if Seconds < 0 then
    Result := 'Unknown time remaining'
  else
    Result := FormatDuration(Seconds) + ' remaining';
end;

{ แปลงจำนวนวินาทีเป็นรูปแบบ วัน/ชั่วโมง/นาที/วินาที เช่น "2h 15m" }
function FormatDuration(Seconds: Int64): string;
var
  D, H, M, S: Int64;
begin
  if Seconds <= 0 then
    Exit('0s');
  D := Seconds div 86400;
  Seconds := Seconds mod 86400;
  H := Seconds div 3600;
  Seconds := Seconds mod 3600;
  M := Seconds div 60;
  S := Seconds mod 60;

  if D > 0 then
    Result := Format('%dd %dh', [D, H])
  else if H > 0 then
    Result := Format('%dh %dm', [H, M])
  else if M > 0 then
    Result := Format('%dm %ds', [M, S])
  else
    Result := Format('%ds', [S]);
end;

{ แปลงสัดส่วน 0.0..1.0 เป็นข้อความเปอร์เซ็นต์ เช่น "100%" หรือ "45.2%" }
function FormatPercent(Frac: Double): string;
var
  Pct: Double;
begin
  Pct := EnsureRange(Frac * 100.0, 0.0, 100.0);
  if Pct >= 99.995 then
    Result := '100%'
  else if Pct < 10.0 then
    Result := Format('%.2f%%', [Pct])
  else
    Result := Format('%.1f%%', [Pct]);
end;

{ สกัดเฉพาะชื่อ Hostname จาก URL ของ Tracker เช่น "https://tracker.opentrackr.org:443/announce" -> "tracker.opentrackr.org" }
function ExtractTrackerHost(const AnnounceUrl: string): string;
var
  S: string;
  P: Integer;
begin
  S := Trim(AnnounceUrl);
  P := Pos('://', S);
  if P > 0 then
    Delete(S, 1, P + 2);
  P := Pos('/', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  P := Pos(':', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  Result := LowerCase(S);
end;

{ TTorrentItem }

function TTorrentItem.IsPaused: Boolean;
begin
  Result := Status = TR_STATUS_STOPPED;
end;

function TTorrentItem.IsDownloading: Boolean;
begin
  Result := (Status = TR_STATUS_DOWNLOAD) or (Status = TR_STATUS_DOWNLOAD_WAIT);
end;

function TTorrentItem.IsSeeding: Boolean;
begin
  Result := (Status = TR_STATUS_SEED) or (Status = TR_STATUS_SEED_WAIT);
end;

function TTorrentItem.IsVerifying: Boolean;
begin
  Result := (Status = TR_STATUS_CHECK) or (Status = TR_STATUS_CHECK_WAIT);
end;

function TTorrentItem.IsQueued: Boolean;
begin
  Result := (Status = TR_STATUS_CHECK_WAIT) or
            (Status = TR_STATUS_DOWNLOAD_WAIT) or
            (Status = TR_STATUS_SEED_WAIT);
end;

function TTorrentItem.IsActive: Boolean;
begin
  Result := (RateDownload > 0) or (RateUpload > 0) or (PeersSendingToUs > 0) or (PeersGettingFromUs > 0);
end;

function TTorrentItem.HasError: Boolean;
begin
  Result := (Error <> 0) and (Trim(ErrorString) <> '');
end;

function TTorrentItem.HaveTotal: Int64;
begin
  Result := HaveValid + HaveUnchecked;
  if (Result = 0) and (SizeWhenDone > 0) then
    Result := Round(SizeWhenDone * PercentDone);
end;

function TTorrentItem.EffectiveSeedRatioLimit(const GlobalRatioLimited: Boolean;
  const GlobalRatioLimit: Double): Double;
begin
  if SeedRatioMode = TR_RATIOLIMIT_SINGLE then
    Result := SeedRatioLimit
  else if (SeedRatioMode = TR_RATIOLIMIT_GLOBAL) and GlobalRatioLimited then
    Result := GlobalRatioLimit
  else
    Result := -1.0;
end;

{ สร้างข้อความสถานะแบบสั้นสำหรับแสดงด้านซ้ายของหลอด Progress Bar ในโหมด Compact View }
function TTorrentItem.ShortStatusString: string;
begin
  if HasError then
    Exit('Error');

  case Status of
    TR_STATUS_STOPPED:
      if IsFinished then
        Result := 'Finished'
      else
        Result := 'Paused';
    TR_STATUS_CHECK_WAIT:
      Result := 'Queued for verification';
    TR_STATUS_CHECK:
      Result := Format('Verifying (%s)', [FormatPercent(PercentDone)]);
    TR_STATUS_DOWNLOAD_WAIT:
      Result := 'Queued for download';
    TR_STATUS_SEED_WAIT:
      Result := 'Queued for seeding';
    TR_STATUS_DOWNLOAD:
      begin
        Result := '';
        if RateDownload > 0 then
          Result := 'Down: ' + FormatSpeed(RateDownload);
        if RateUpload > 0 then
        begin
          if Result <> '' then Result := Result + '  ';
          Result := Result + 'Up: ' + FormatSpeed(RateUpload);
        end;
        if Result = '' then
          Result := 'Idle';
      end;
    TR_STATUS_SEED:
      begin
        if RateUpload > 0 then
          Result := Format('Ratio: %s, Up: %s', [FormatRatio(UploadRatio), FormatSpeed(RateUpload)])
        else
          Result := Format('Ratio: %s', [FormatRatio(UploadRatio)]);
      end;
  else
    Result := '';
  end;
end;

{ สร้างข้อความสถานะแบบละเอียดสำหรับแสดงบรรทัดที่ 2 ในโหมด Full View และหน้าต่าง Properties }
function TTorrentItem.FullStatusString: string;
begin
  if HasError then
    Exit('Error: ' + ErrorString);

  case Status of
    TR_STATUS_STOPPED:
      if IsFinished then
        Result := 'Finished'
      else
        Result := 'Paused';
    TR_STATUS_CHECK_WAIT:
      Result := 'Queued for verification';
    TR_STATUS_CHECK:
      Result := Format('Verifying local data (%s tested)', [FormatPercent(PercentDone)]);
    TR_STATUS_DOWNLOAD_WAIT:
      Result := 'Waiting to download';
    TR_STATUS_SEED_WAIT:
      Result := 'Waiting to seed';
    TR_STATUS_DOWNLOAD:
      begin
        if MetadataPercentComplete < 1.0 then
          Result := Format('Downloading metadata from %d peers (%s)',
            [PeersConnected, FormatPercent(MetadataPercentComplete)])
        else
          Result := Format('Downloading from %d of %d peers - Down: %s  Up: %s',
            [PeersSendingToUs, PeersConnected, FormatSpeed(RateDownload), FormatSpeed(RateUpload)]);
      end;
    TR_STATUS_SEED:
      Result := Format('Seeding to %d of %d peers - Up: %s',
        [PeersGettingFromUs, PeersConnected, FormatSpeed(RateUpload)]);
  else
    Result := 'Unknown';
  end;
end;

{ สร้างข้อความสรุปความคืบหน้าและยอดอัปโหลดสำหรับแสดงบรรทัดที่ 4 ในโหมด Full View }
function TTorrentItem.ProgressSummaryString(const GlobalRatioLimited: Boolean;
  const GlobalRatioLimit: Double): string;
var
  Goal: Double;
begin
  Goal := EffectiveSeedRatioLimit(GlobalRatioLimited, GlobalRatioLimit);
  if MetadataPercentComplete < 1.0 then
  begin
    Result := Format('Magnetized transfer - retrieving metadata (%s)',
      [FormatPercent(MetadataPercentComplete)]);
  end
  else if LeftUntilDone > 0 then
  begin
    Result := Format('%s of %s (%s)',
      [FormatSize(HaveTotal), FormatSize(SizeWhenDone), FormatPercent(PercentDone)]);
    if IsDownloading and (ETA >= 0) then
      Result := Result + ' - ' + FormatETA(ETA);
  end
  else
  begin
    if Goal > 0 then
      Result := Format('%s, uploaded %s (Ratio: %s, Goal: %s)',
        [FormatSize(TotalSize), FormatSize(UploadedEver), FormatRatio(UploadRatio), FormatRatio(Goal)])
    else
      Result := Format('%s, uploaded %s (Ratio: %s)',
        [FormatSize(TotalSize), FormatSize(UploadedEver), FormatRatio(UploadRatio)]);
  end;
end;

function HasCliFlag(const Flag: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), Flag) then
      Exit(True);
end;

function GetWindowsAutoStart(out StartMinimized: Boolean): Boolean;
{$IFDEF WINDOWS}
const
  RUN_KEY = '\Software\Microsoft\Windows\CurrentVersion\Run';
  VAL_NAME = 'Transmission';
var
  Reg: TRegistry;
  Cmd: string;
begin
  Result := False;
  StartMinimized := False;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(RUN_KEY) and Reg.ValueExists(VAL_NAME) then
    begin
      Cmd := Trim(Reg.ReadString(VAL_NAME));
      Result := Cmd <> '';
      StartMinimized := Pos('--minimized', LowerCase(Cmd)) > 0;
    end;
  finally
    Reg.Free;
  end;
end;
{$ELSE}
begin
  StartMinimized := False;
  Result := False;
end;
{$ENDIF}

function SetWindowsAutoStart(Enabled, StartMinimized: Boolean): Boolean;
{$IFDEF WINDOWS}
const
  RUN_KEY = '\Software\Microsoft\Windows\CurrentVersion\Run';
  VAL_NAME = 'Transmission';
var
  Reg: TRegistry;
  Cmd: string;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(RUN_KEY, True) then
    begin
      if Enabled then
      begin
        Cmd := '"' + ParamStr(0) + '"';
        if StartMinimized then
          Cmd := Cmd + ' --minimized';
        Reg.WriteString(VAL_NAME, Cmd);
      end
      else if Reg.ValueExists(VAL_NAME) then
        Reg.DeleteValue(VAL_NAME);
      Result := True;
    end;
  finally
    Reg.Free;
  end;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

{$IFDEF WINDOWS}
function WinSetThreadExecutionState(esFlags: DWORD): DWORD; stdcall;
  external 'kernel32.dll' name 'SetThreadExecutionState';
procedure WinSHChangeNotify(wEventId: LongInt; uFlags: UINT; dwItem1, dwItem2: Pointer); stdcall;
  external 'shell32.dll' name 'SHChangeNotify';

const
  TORRENT_PROG_ID = 'TransmissionLaz.Torrent';

function ReadHkcuStr(const SubKey, ValName: string): string;
var
  Reg: TRegistry;
begin
  Result := '';
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(SubKey) and Reg.ValueExists(ValName) then
      Result := Trim(Reg.ReadString(ValName));
  finally
    Reg.Free;
  end;
end;

function WriteHkcuStr(const SubKey, ValName, Value: string): Boolean;
var
  Reg: TRegistry;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(SubKey, True) then
    begin
      Reg.WriteString(ValName, Value);
      Result := True;
    end;
  finally
    Reg.Free;
  end;
end;

procedure DeleteHkcuKeysBottomUp(const Keys: array of string);
var
  Reg: TRegistry;
  I: Integer;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    for I := Low(Keys) to High(Keys) do
      if Reg.KeyExists(Keys[I]) then
        Reg.DeleteKey(Keys[I]);
  finally
    Reg.Free;
  end;
end;

function CommandPointsToSelf(const Cmd: string): Boolean;
var
  ExePath: string;
begin
  ExePath := LowerCase(ParamStr(0));
  Result := (Cmd <> '') and (Pos(ExePath, LowerCase(Cmd)) > 0);
end;

procedure NotifyShellAssocChanged;
begin
  WinSHChangeNotify($08000000 {SHCNE_ASSOCCHANGED}, 0 {SHCNF_IDLIST}, nil, nil);
end;
{$ENDIF}

function GetTorrentFileAssociation: Boolean;
{$IFDEF WINDOWS}
var
  ProgId, Cmd: string;
begin
  ProgId := ReadHkcuStr('\Software\Classes\.torrent', '');
  if not SameText(ProgId, TORRENT_PROG_ID) then
    Exit(False);
  Cmd := ReadHkcuStr('\Software\Classes\' + TORRENT_PROG_ID + '\shell\open\command', '');
  Result := CommandPointsToSelf(Cmd);
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

function SetTorrentFileAssociation(Enabled: Boolean): Boolean;
{$IFDEF WINDOWS}
var
  ExePath, OpenCmd: string;
  Reg: TRegistry;
begin
  Result := False;
  ExePath := ParamStr(0);
  OpenCmd := '"' + ExePath + '" "%1"';
  if Enabled then
  begin
    Result :=
      WriteHkcuStr('\Software\Classes\.torrent', '', TORRENT_PROG_ID) and
      WriteHkcuStr('\Software\Classes\.torrent', 'Content Type', 'application/x-bittorrent') and
      WriteHkcuStr('\Software\Classes\' + TORRENT_PROG_ID, '', 'BitTorrent File') and
      WriteHkcuStr('\Software\Classes\' + TORRENT_PROG_ID + '\DefaultIcon', '', '"' + ExePath + '",0') and
      WriteHkcuStr('\Software\Classes\' + TORRENT_PROG_ID + '\shell\open\command', '', OpenCmd);
  end
  else
  begin
    if SameText(ReadHkcuStr('\Software\Classes\.torrent', ''), TORRENT_PROG_ID) then
    begin
      Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
      try
        Reg.RootKey := HKEY_CURRENT_USER;
        if Reg.OpenKey('\Software\Classes\.torrent', False) and Reg.ValueExists('') then
          Reg.DeleteValue('');
      finally
        Reg.Free;
      end;
    end;
    DeleteHkcuKeysBottomUp([
      '\Software\Classes\' + TORRENT_PROG_ID + '\shell\open\command',
      '\Software\Classes\' + TORRENT_PROG_ID + '\shell\open',
      '\Software\Classes\' + TORRENT_PROG_ID + '\shell',
      '\Software\Classes\' + TORRENT_PROG_ID + '\DefaultIcon',
      '\Software\Classes\' + TORRENT_PROG_ID
    ]);
    Result := True;
  end;
  NotifyShellAssocChanged;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

function GetMagnetProtocolAssociation: Boolean;
{$IFDEF WINDOWS}
var
  Reg: TRegistry;
  HasProto: Boolean;
  Cmd: string;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    HasProto := Reg.OpenKeyReadOnly('\Software\Classes\magnet') and Reg.ValueExists('URL Protocol');
  finally
    Reg.Free;
  end;
  if not HasProto then Exit(False);
  Cmd := ReadHkcuStr('\Software\Classes\magnet\shell\open\command', '');
  Result := CommandPointsToSelf(Cmd);
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

function SetMagnetProtocolAssociation(Enabled: Boolean): Boolean;
{$IFDEF WINDOWS}
var
  ExePath, OpenCmd: string;
begin
  Result := False;
  ExePath := ParamStr(0);
  OpenCmd := '"' + ExePath + '" "%1"';
  if Enabled then
  begin
    Result :=
      WriteHkcuStr('\Software\Classes\magnet', '', 'URL:Magnet Protocol') and
      WriteHkcuStr('\Software\Classes\magnet', 'URL Protocol', '') and
      WriteHkcuStr('\Software\Classes\magnet\DefaultIcon', '', '"' + ExePath + '",0') and
      WriteHkcuStr('\Software\Classes\magnet\shell\open\command', '', OpenCmd);
  end
  else
  begin
    if CommandPointsToSelf(ReadHkcuStr('\Software\Classes\magnet\shell\open\command', '')) then
      DeleteHkcuKeysBottomUp([
        '\Software\Classes\magnet\shell\open\command',
        '\Software\Classes\magnet\shell\open',
        '\Software\Classes\magnet\shell',
        '\Software\Classes\magnet\DefaultIcon',
        '\Software\Classes\magnet'
      ]);
    Result := True;
  end;
  NotifyShellAssocChanged;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

procedure SetPreventSystemSleep(Active: Boolean);
{$IFDEF WINDOWS}
const
  ES_CONTINUOUS      = DWORD($80000000);
  ES_SYSTEM_REQUIRED = DWORD($00000001);
begin
  if Active then
    WinSetThreadExecutionState(ES_CONTINUOUS or ES_SYSTEM_REQUIRED)
  else
    WinSetThreadExecutionState(ES_CONTINUOUS);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure PlayCompletionSound;
begin
{$IFDEF WINDOWS}
  MessageBeep(MB_ICONASTERISK);
{$ENDIF}
end;

function GetDefaultPortableDataDir: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'data';
end;

function NormalizeWinDirPath(const S: string): string;
begin
  Result := Trim(StringReplace(S, '/', PathDelim, [rfReplaceAll]));
  if (Length(Result) > 3) and (Result[Length(Result)] = PathDelim) then
    Result := ExcludeTrailingPathDelimiter(Result);
end;

procedure AddUniqueDir(List: TStrings; const DirPath: string; PutAtTop: Boolean = False);
var
  Clean: string;
  I, ExistingIdx: Integer;
begin
  if List = nil then Exit;
  Clean := NormalizeWinDirPath(DirPath);
  if Clean = '' then Exit;

  ExistingIdx := -1;
  for I := 0 to List.Count - 1 do
    if SameText(NormalizeWinDirPath(List[I]), Clean) then
    begin
      ExistingIdx := I;
      Break;
    end;

  if ExistingIdx >= 0 then
  begin
    if PutAtTop and (ExistingIdx > 0) then
    begin
      List.Delete(ExistingIdx);
      List.Insert(0, Clean);
    end;
    Exit;
  end;

  if PutAtTop then
    List.Insert(0, Clean)
  else
    List.Add(Clean);
end;

function LoadDestinationDirHistory(OutDirs: TStrings; const FallbackDefaultDir: string): string;
var
  IniPath, LastDir, ItemDir, HistPath, DataDir: string;
  Ini: TIniFile;
  Count, I: Integer;
  HistMgr: TDownloadHistoryManager;
begin
  if OutDirs <> nil then
    OutDirs.Clear;

  IniPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'transmission_laz.ini';
  LastDir := '';
  DataDir := '';

  if FileExists(IniPath) then
  begin
    Ini := TIniFile.Create(IniPath);
    try
      LastDir := NormalizeWinDirPath(Ini.ReadString('DestinationHistory', 'LastDir', ''));
      if LastDir <> '' then
        AddUniqueDir(OutDirs, LastDir);

      Count := EnsureRange(Ini.ReadInteger('DestinationHistory', 'Count', 0), 0, 30);
      for I := 0 to Count - 1 do
      begin
        ItemDir := NormalizeWinDirPath(Ini.ReadString('DestinationHistory', 'Dir' + IntToStr(I), ''));
        if ItemDir <> '' then
          AddUniqueDir(OutDirs, ItemDir);
      end;
      DataDir := Trim(Ini.ReadString('Session', 'DataDir', ''));
    finally
      Ini.Free;
    end;
  end;

  // ดึงโฟลเดอร์ที่เคยใช้งานจากประวัติการดาวน์โหลด (download_history.json) มาเติมให้อัตโนมัติด้วย
  if DataDir = '' then
    DataDir := GetDefaultPortableDataDir;
  HistPath := IncludeTrailingPathDelimiter(DataDir) + 'download_history.json';
  if FileExists(HistPath) then
  begin
    HistMgr := TDownloadHistoryManager.Create;
    try
      HistMgr.LoadFromFile(HistPath);
      for I := 0 to HistMgr.Count - 1 do
        if HistMgr.GetItem(I) <> nil then
          AddUniqueDir(OutDirs, HistMgr.GetItem(I).DownloadDir);
    finally
      HistMgr.Free;
    end;
  end;

  if Trim(FallbackDefaultDir) <> '' then
    AddUniqueDir(OutDirs, FallbackDefaultDir);

  if LastDir <> '' then
    Result := LastDir
  else if (OutDirs <> nil) and (OutDirs.Count > 0) then
    Result := OutDirs[0]
  else
    Result := NormalizeWinDirPath(FallbackDefaultDir);
end;

procedure SaveDestinationDirToHistory(const DirPath: string);
const
  MAX_RECENT_DIRS = 20;
var
  Clean, IniPath, KeyName: string;
  Dirs: TStringList;
  Ini: TIniFile;
  I: Integer;
begin
  Clean := NormalizeWinDirPath(DirPath);
  if Clean = '' then Exit;

  Dirs := TStringList.Create;
  try
    LoadDestinationDirHistory(Dirs, '');
    AddUniqueDir(Dirs, Clean, True);
    while Dirs.Count > MAX_RECENT_DIRS do
      Dirs.Delete(Dirs.Count - 1);

    IniPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'transmission_laz.ini';
    try
      Ini := TIniFile.Create(IniPath);
      try
        Ini.WriteString('DestinationHistory', 'LastDir', Clean);
        Ini.WriteInteger('DestinationHistory', 'Count', Dirs.Count);
        for I := 0 to Dirs.Count - 1 do
        begin
          KeyName := 'Dir' + IntToStr(I);
          Ini.WriteString('DestinationHistory', KeyName, Dirs[I]);
        end;
      finally
        Ini.Free;
      end;
    except
    end;
  finally
    Dirs.Free;
  end;
end;

function FileToRawStr(const FilePath: string): string;
var
  FS: TFileStream;
begin
  Result := '';
  if not FileExists(FilePath) then Exit;
  FS := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyNone);
  try
    if FS.Size > 0 then
    begin
      SetLength(Result, FS.Size);
      FS.ReadBuffer(Result[1], FS.Size);
    end;
  finally
    FS.Free;
  end;
end;

procedure RawStrToFile(const FilePath, Data: string);
var
  FS: TFileStream;
begin
  ForceDirectories(ExtractFileDir(FilePath));
  FS := TFileStream.Create(FilePath, fmCreate);
  try
    if Length(Data) > 0 then
      FS.WriteBuffer(Data[1], Length(Data));
  finally
    FS.Free;
  end;
end;

{ TDownloadHistoryManager }

constructor TDownloadHistoryManager.Create;
begin
  FItems := TList.Create;
  FDirty := False;
end;

destructor TDownloadHistoryManager.Destroy;
begin
  Clear;
  FItems.Free;
  inherited Destroy;
end;

procedure TDownloadHistoryManager.Clear;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    TObject(FItems[I]).Free;
  FItems.Clear;
  FDirty := True;
end;

function TDownloadHistoryManager.Count: Integer;
begin
  Result := FItems.Count;
end;

function TDownloadHistoryManager.GetItem(Idx: Integer): THistoryItem;
begin
  if (Idx >= 0) and (Idx < FItems.Count) then
    Result := THistoryItem(FItems[Idx])
  else
    Result := nil;
end;

function TDownloadHistoryManager.FindByHash(const HashStr: string): THistoryItem;
var
  I: Integer;
  H: THistoryItem;
begin
  Result := nil;
  if HashStr = '' then Exit;
  for I := 0 to FItems.Count - 1 do
  begin
    H := THistoryItem(FItems[I]);
    if SameText(H.HashString, HashStr) then
      Exit(H);
  end;
end;

function TDownloadHistoryManager.LoadFromFile(const FilePath: string): Boolean;
var
  Raw: string;
  Data: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  H: THistoryItem;
begin
  Result := False;
  Clear;
  FDirty := False;
  if not FileExists(FilePath) then Exit;
  Raw := FileToRawStr(FilePath);
  if Trim(Raw) = '' then Exit;
  try
    Data := GetJSON(Raw);
    try
      if Data is TJSONArray then
      begin
        Arr := TJSONArray(Data);
        for I := 0 to Arr.Count - 1 do
        begin
          if not (Arr.Items[I] is TJSONObject) then Continue;
          Obj := TJSONObject(Arr.Items[I]);
          H := THistoryItem.Create;
          H.HashString := Obj.Get('hash', '');
          H.Name := Obj.Get('name', '');
          H.TotalSize := Obj.Get('totalSize', Int64(0));
          H.DownloadedEver := Obj.Get('downloadedEver', Int64(0));
          H.UploadedEver := Obj.Get('uploadedEver', Int64(0));
          H.UploadRatio := Obj.Get('uploadRatio', 0.0);
          H.DownloadDir := Obj.Get('downloadDir', '');
          H.MagnetLink := Obj.Get('magnetLink', '');
          H.AddedDate := Obj.Get('addedDate', Int64(0));
          H.DoneDate := Obj.Get('doneDate', Int64(0));
          H.LastSeenDate := Obj.Get('lastSeenDate', Int64(0));
          H.Completed := Obj.Get('completed', False);
          if H.HashString <> '' then
            FItems.Add(H)
          else
            H.Free;
        end;
        Result := True;
      end;
    finally
      Data.Free;
    end;
  except
    Result := False;
  end;
end;

function TDownloadHistoryManager.SaveToFile(const FilePath: string): Boolean;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  H: THistoryItem;
begin
  Result := False;
  Arr := TJSONArray.Create;
  try
    for I := 0 to FItems.Count - 1 do
    begin
      H := THistoryItem(FItems[I]);
      Obj := TJSONObject.Create;
      Obj.Add('hash', H.HashString);
      Obj.Add('name', H.Name);
      Obj.Add('totalSize', H.TotalSize);
      Obj.Add('downloadedEver', H.DownloadedEver);
      Obj.Add('uploadedEver', H.UploadedEver);
      Obj.Add('uploadRatio', H.UploadRatio);
      Obj.Add('downloadDir', H.DownloadDir);
      Obj.Add('magnetLink', H.MagnetLink);
      Obj.Add('addedDate', H.AddedDate);
      Obj.Add('doneDate', H.DoneDate);
      Obj.Add('lastSeenDate', H.LastSeenDate);
      Obj.Add('completed', H.Completed);
      Arr.Add(Obj);
    end;
    RawStrToFile(FilePath, Arr.FormatJSON);
    FDirty := False;
    Result := True;
  finally
    Arr.Free;
  end;
end;

function TDownloadHistoryManager.SyncFromTorrents(Torrents: TList; const FilePath: string;
  ForceSave: Boolean): Boolean;
var
  I: Integer;
  T: TTorrentItem;
  H: THistoryItem;
  IsDone, Changed: Boolean;
  NowUnix: Int64;
begin
  Result := False;
  if Torrents = nil then Exit;
  Changed := False;
  NowUnix := Trunc((Now - EncodeDate(1970, 1, 1)) * 86400);
  for I := 0 to Torrents.Count - 1 do
  begin
    T := TTorrentItem(Torrents[I]);
    if Trim(T.HashString) = '' then Continue;
    IsDone := (T.PercentDone >= 0.9999) and (T.LeftUntilDone = 0) and (T.TotalSize > 0);
    H := FindByHash(T.HashString);
    if H = nil then
    begin
      H := THistoryItem.Create;
      H.HashString := T.HashString;
      H.Name := T.Name;
      H.TotalSize := T.TotalSize;
      H.DownloadedEver := T.DownloadedEver;
      H.UploadedEver := T.UploadedEver;
      H.UploadRatio := T.UploadRatio;
      H.DownloadDir := T.DownloadDir;
      H.MagnetLink := T.MagnetLink;
      H.AddedDate := T.AddedDate;
      H.DoneDate := T.DoneDate;
      H.LastSeenDate := NowUnix;
      H.Completed := IsDone;
      FItems.Add(H);
      Changed := True;
    end
    else
    begin
      if (T.Name <> '') and (H.Name <> T.Name) then begin H.Name := T.Name; Changed := True; end;
      if (T.TotalSize > 0) and (H.TotalSize <> T.TotalSize) then begin H.TotalSize := T.TotalSize; Changed := True; end;
      if (T.MagnetLink <> '') and (H.MagnetLink <> T.MagnetLink) then begin H.MagnetLink := T.MagnetLink; Changed := True; end;
      if (T.DownloadDir <> '') and (H.DownloadDir <> T.DownloadDir) then begin H.DownloadDir := T.DownloadDir; Changed := True; end;
      if (T.DoneDate > 0) and (H.DoneDate <> T.DoneDate) then begin H.DoneDate := T.DoneDate; Changed := True; end;
      if IsDone and (not H.Completed) then
      begin
        H.Completed := True;
        if H.DoneDate <= 0 then H.DoneDate := NowUnix;
        Changed := True;
      end;
      if T.DownloadedEver > H.DownloadedEver then H.DownloadedEver := T.DownloadedEver;
      if T.UploadedEver > H.UploadedEver then H.UploadedEver := T.UploadedEver;
      H.UploadRatio := T.UploadRatio;
      H.LastSeenDate := NowUnix;
    end;
  end;
  if Changed then FDirty := True;
  if (FDirty and (Changed or ForceSave)) and (FilePath <> '') then
    Result := SaveToFile(FilePath);
end;

procedure TDownloadHistoryManager.RemoveByHash(const HashStr: string);
var
  I: Integer;
  H: THistoryItem;
begin
  for I := FItems.Count - 1 downto 0 do
  begin
    H := THistoryItem(FItems[I]);
    if SameText(H.HashString, HashStr) then
    begin
      H.Free;
      FItems.Delete(I);
      FDirty := True;
    end;
  end;
end;

procedure PackDirFiles(const FolderPath, Pattern: string; OutArr: TJSONArray);
var
  SR: TSearchRec;
  DirSep, Raw: string;
  Obj: TJSONObject;
begin
  if not DirectoryExists(FolderPath) then Exit;
  DirSep := IncludeTrailingPathDelimiter(FolderPath);
  if FindFirst(DirSep + Pattern, faAnyFile and not faDirectory, SR) = 0 then
  begin
    try
      repeat
        if (SR.Attr and faDirectory) <> 0 then Continue;
        Raw := FileToRawStr(DirSep + SR.Name);
        Obj := TJSONObject.Create;
        Obj.Add('name', SR.Name);
        Obj.Add('b64', EncodeStringBase64(Raw));
        OutArr.Add(Obj);
      until FindNext(SR) <> 0;
    finally
      SysUtils.FindClose(SR);
    end;
  end;
end;

function ExportPortableBackup(const DestFilePath, DataDir, IniPath: string;
  History: TDownloadHistoryManager): Boolean;
var
  Root: TJSONObject;
  TorArr, ResArr: TJSONArray;
  HistRaw, DirSep: string;
  HistData: TJSONData;
begin
  Result := False;
  Root := TJSONObject.Create;
  try
    DirSep := IncludeTrailingPathDelimiter(DataDir);
    if History <> nil then
      History.SaveToFile(DirSep + 'download_history.json');

    Root.Add('version', 1);
    Root.Add('appIni', EncodeStringBase64(FileToRawStr(IniPath)));
    Root.Add('settingsJson', EncodeStringBase64(FileToRawStr(DirSep + 'settings.json')));
    Root.Add('statsJson', EncodeStringBase64(FileToRawStr(DirSep + 'stats.json')));

    HistRaw := FileToRawStr(DirSep + 'download_history.json');
    if Trim(HistRaw) <> '' then
    begin
      try
        HistData := GetJSON(HistRaw);
        Root.Add('history', HistData);
      except
        Root.Add('history', TJSONArray.Create);
      end;
    end
    else
      Root.Add('history', TJSONArray.Create);

    TorArr := TJSONArray.Create;
    PackDirFiles(DirSep + 'Torrents', '*', TorArr);
    Root.Add('torrents', TorArr);

    ResArr := TJSONArray.Create;
    PackDirFiles(DirSep + 'Resume', '*', ResArr);
    Root.Add('resume', ResArr);

    RawStrToFile(DestFilePath, Root.FormatJSON);
    Result := True;
  finally
    Root.Free;
  end;
end;

function ImportPortableBackup(const SrcFilePath, DataDir: string;
  History: TDownloadHistoryManager; out RestoredFiles: Integer): Boolean;
var
  Raw, DirSep, B64, FileName: string;
  Data: TJSONData;
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := False;
  RestoredFiles := 0;
  if not FileExists(SrcFilePath) then Exit;
  Raw := FileToRawStr(SrcFilePath);
  if Trim(Raw) = '' then Exit;
  DirSep := IncludeTrailingPathDelimiter(DataDir);
  ForceDirectories(DirSep);

  Data := GetJSON(Raw);
  try
    if not (Data is TJSONObject) then Exit(False);
    Root := TJSONObject(Data);

    B64 := Root.Get('settingsJson', '');
    if B64 <> '' then
    begin
      RawStrToFile(DirSep + 'settings.json', DecodeStringBase64(B64));
      Inc(RestoredFiles);
    end;
    B64 := Root.Get('statsJson', '');
    if B64 <> '' then
    begin
      RawStrToFile(DirSep + 'stats.json', DecodeStringBase64(B64));
      Inc(RestoredFiles);
    end;

    Arr := Root.Find('torrents') as TJSONArray;
    if Arr <> nil then
    begin
      for I := 0 to Arr.Count - 1 do
      begin
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          FileName := ExtractFileName(Obj.Get('name', ''));
          B64 := Obj.Get('b64', '');
          if (FileName <> '') and (B64 <> '') then
          begin
            RawStrToFile(DirSep + 'Torrents' + PathDelim + FileName, DecodeStringBase64(B64));
            Inc(RestoredFiles);
          end;
        end;
      end;
    end;

    Arr := Root.Find('resume') as TJSONArray;
    if Arr <> nil then
    begin
      for I := 0 to Arr.Count - 1 do
      begin
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          FileName := ExtractFileName(Obj.Get('name', ''));
          B64 := Obj.Get('b64', '');
          if (FileName <> '') and (B64 <> '') then
          begin
            RawStrToFile(DirSep + 'Resume' + PathDelim + FileName, DecodeStringBase64(B64));
            Inc(RestoredFiles);
          end;
        end;
      end;
    end;

    Arr := Root.Find('history') as TJSONArray;
    if Arr <> nil then
    begin
      RawStrToFile(DirSep + 'download_history.json', Arr.FormatJSON);
      if History <> nil then
        History.LoadFromFile(DirSep + 'download_history.json');
      Inc(RestoredFiles);
    end;

    Result := True;
  finally
    Data.Free;
  end;
end;

var
  GSingleInstanceMutex: THandle = 0;
  GSingleInstanceMap: THandle = 0;
  {$IFDEF WINDOWS}
  GSubclassedHwnd: HWND = 0;
  GPrevWndProc: PtrUInt = 0;
  GOnSingleInstancePayload: TSingleInstancePayloadEvent = nil;
  {$ENDIF}

function AcquireSingleInstanceLock: Boolean;
{$IFDEF WINDOWS}
var
  Err: DWORD;
begin
  if GSingleInstanceMutex <> 0 then
    Exit(True);
  GSingleInstanceMutex := CreateMutexW(nil, True,
    PWideChar(UnicodeString('Local\TransmissionLazSingleInstance_V1')));
  if GSingleInstanceMutex = 0 then
    Exit(True); // ไม่บล็อกการเปิดหากระบบสร้าง Mutex ไม่สำเร็จ
  Err := GetLastError;
  if Err = ERROR_ALREADY_EXISTS then
  begin
    CloseHandle(GSingleInstanceMutex);
    GSingleInstanceMutex := 0;
    Exit(False);
  end;
  Result := True;
end;
{$ELSE}
begin
  Result := True;
end;
{$ENDIF}

procedure ReleaseSingleInstanceLock;
begin
{$IFDEF WINDOWS}
  if GSingleInstanceMutex <> 0 then
  begin
    ReleaseMutex(GSingleInstanceMutex);
    CloseHandle(GSingleInstanceMutex);
    GSingleInstanceMutex := 0;
  end;
{$ENDIF}
end;

procedure UnregisterSingleInstanceWindow;
begin
{$IFDEF WINDOWS}
  if (GSubclassedHwnd <> 0) and IsWindow(GSubclassedHwnd) and (GPrevWndProc <> 0) then
  begin
    SetWindowLongPtrW(GSubclassedHwnd, GWLP_WNDPROC, LONG_PTR(GPrevWndProc));
    GSubclassedHwnd := 0;
    GPrevWndProc := 0;
  end;
  GOnSingleInstancePayload := nil;
  if GSingleInstanceMap <> 0 then
  begin
    CloseHandle(GSingleInstanceMap);
    GSingleInstanceMap := 0;
  end;
{$ENDIF}
end;

{$IFDEF WINDOWS}
function SingleInstanceSubclassProc(ahwnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  CDS: PCopyDataStruct;
  Payload: string;
begin
  if uMsg = WM_COPYDATA then
  begin
    CDS := {%H-}PCopyDataStruct(lParam);
    if (CDS <> nil) and (CDS^.dwData = SINGLE_INSTANCE_COPYDATA_ID) then
    begin
      Payload := '';
      if (CDS^.cbData > 0) and (CDS^.lpData <> nil) then
      begin
        SetLength(Payload, CDS^.cbData);
        Move(CDS^.lpData^, Payload[1], CDS^.cbData);
      end;
      if Assigned(GOnSingleInstancePayload) then
        GOnSingleInstancePayload(Payload);
      Exit(1);
    end;
  end;
  if GPrevWndProc <> 0 then
    Result := CallWindowProcW(WNDPROC(GPrevWndProc), ahwnd, uMsg, wParam, lParam)
  else
    Result := DefWindowProcW(ahwnd, uMsg, wParam, lParam);
end;
{$ENDIF}

procedure RegisterMainWindowForSingleInstance(MainHwnd: PtrUInt; OnPayload: TSingleInstancePayloadEvent = nil);
{$IFDEF WINDOWS}
var
  P: PPtrUInt;
begin
  UnregisterSingleInstanceWindow;
  GOnSingleInstancePayload := OnPayload;
  if (MainHwnd <> 0) and IsWindow(HWND(MainHwnd)) then
  begin
    GPrevWndProc := PtrUInt(GetWindowLongPtrW(HWND(MainHwnd), GWLP_WNDPROC));
    if (GPrevWndProc <> 0) and (GPrevWndProc <> PtrUInt(@SingleInstanceSubclassProc)) then
    begin
      SetWindowLongPtrW(HWND(MainHwnd), GWLP_WNDPROC, LONG_PTR(PtrUInt(@SingleInstanceSubclassProc)));
      GSubclassedHwnd := HWND(MainHwnd);
    end;
  end;
  GSingleInstanceMap := CreateFileMappingW(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE,
    0, SizeOf(PtrUInt), PWideChar(UnicodeString('Local\TransmissionLazMainHwnd_V1')));
  if GSingleInstanceMap <> 0 then
  begin
    P := MapViewOfFile(GSingleInstanceMap, FILE_MAP_WRITE, 0, 0, SizeOf(PtrUInt));
    if P <> nil then
    begin
      P^ := MainHwnd;
      UnmapViewOfFile(P);
    end;
  end;
end;
{$ELSE}
begin
end;
{$ENDIF}

{$IFDEF WINDOWS}
function AllowSetForegroundWindow(dwProcessId: DWORD): BOOL; stdcall; external 'user32.dll' name 'AllowSetForegroundWindow';
{$ENDIF}

procedure NotifyExistingInstance;
{$IFDEF WINDOWS}
var
  Retry, I: Integer;
  HMap: THandle;
  P: PPtrUInt;
  TargetHwnd: HWND;
  TargetPid: DWORD;
  ArgList, PayloadStr, OneArg: string;
  ShouldActivate: Boolean;
  CDS: COPYDATASTRUCT;
begin
  TargetHwnd := 0;
  for Retry := 1 to 20 do
  begin
    HMap := OpenFileMappingW(FILE_MAP_READ, False,
      PWideChar(UnicodeString('Local\TransmissionLazMainHwnd_V1')));
    if HMap <> 0 then
    begin
      try
        P := MapViewOfFile(HMap, FILE_MAP_READ, 0, 0, SizeOf(PtrUInt));
        if P <> nil then
        begin
          TargetHwnd := HWND(P^);
          UnmapViewOfFile(P);
        end;
      finally
        CloseHandle(HMap);
      end;
      if (TargetHwnd <> 0) and IsWindow(TargetHwnd) then Break;
      TargetHwnd := 0;
    end;
    Sleep(50);
  end;

  if (TargetHwnd = 0) or (not IsWindow(TargetHwnd)) then
    TargetHwnd := FindWindowW(nil, PWideChar(UnicodeString('Transmission')));
  if (TargetHwnd = 0) or (not IsWindow(TargetHwnd)) then Exit;

  ArgList := '';
  for I := 1 to ParamCount do
  begin
    OneArg := Trim(ParamStr(I));
    if (OneArg = '') or SameText(OneArg, '--minimized') then Continue;
    if ArgList <> '' then ArgList := ArgList + #10;
    ArgList := ArgList + OneArg;
  end;

  ShouldActivate := (not HasCliFlag('--minimized')) or (ArgList <> '');
  if ShouldActivate then
    PayloadStr := '1'
  else
    PayloadStr := '0';
  if ArgList <> '' then
    PayloadStr := PayloadStr + #10 + ArgList;

  TargetPid := 0;
  GetWindowThreadProcessId(TargetHwnd, @TargetPid);
  if (TargetPid <> 0) and ShouldActivate then
    AllowSetForegroundWindow(TargetPid);

  CDS.dwData := SINGLE_INSTANCE_COPYDATA_ID;
  CDS.cbData := Length(PayloadStr);
  if CDS.cbData > 0 then
    CDS.lpData := PAnsiChar(PayloadStr)
  else
    CDS.lpData := nil;

  SendMessageW(TargetHwnd, WM_COPYDATA, 0, LPARAM(@CDS));
  if ShouldActivate then
    SetForegroundWindow(TargetHwnd);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure ForceForegroundHwnd(HwndVal: PtrUInt);
{$IFDEF WINDOWS}
var
  H: HWND;
begin
  H := HWND(HwndVal);
  if H = 0 then Exit;
  if IsIconic(H) then
    ShowWindow(H, SW_RESTORE)
  else
    ShowWindow(H, SW_SHOW);
  SetForegroundWindow(H);
end;
{$ELSE}
begin
end;
{$ENDIF}

function GetEmbeddedBinDir(const PreferredDataDir: string): string;
var
  BaseDir, FallbackDir, TestFile: string;
  FS: TFileStream;
begin
  BaseDir := Trim(PreferredDataDir);
  if BaseDir = '' then
    BaseDir := GetDefaultPortableDataDir;
  Result := IncludeTrailingPathDelimiter(BaseDir) + 'bin';
  if ForceDirectories(Result) then
  begin
    TestFile := IncludeTrailingPathDelimiter(Result) + '.write_chk';
    try
      FS := TFileStream.Create(TestFile, fmCreate);
      FS.Free;
      SysUtils.DeleteFile(TestFile);
      Exit;
    except
    end;
  end;

  FallbackDir := Trim(SysUtils.GetEnvironmentVariable('LOCALAPPDATA'));
  if FallbackDir = '' then
    FallbackDir := GetTempDir(False);
  Result := IncludeTrailingPathDelimiter(FallbackDir) + 'TransmissionLaz' + PathDelim + 'bin';
  ForceDirectories(Result);
end;

function ComputeStreamFnv1aHex(S: TStream): string;
var
  Buf: array[0..8191] of Byte;
  N, I: Integer;
  H: QWord;
begin
  S.Position := 0;
  H := QWord($CBF29CE484222325);
  repeat
    N := S.Read(Buf[0], SizeOf(Buf));
    for I := 0 to N - 1 do
    begin
      H := H xor Buf[I];
      H := H * QWord($100000001B3);
    end;
  until N = 0;
  S.Position := 0;
  Result := IntToHex(H, 16) + '_' + IntToStr(S.Size);
end;

function EnsureEmbeddedAsset(const ResName, TargetFilePath: string): Boolean;
var
  ResStr: TResourceStream;
  Decomp: TDecompressionStream;
  OutStr: TFileStream;
  TmpPath, SigPath, ExpectedSig, CurSig: string;
  Buf: array[0..65535] of Byte;
  N: Integer;
  SL: TStringList;
begin
  Result := False;
  {$IFDEF WINDOWS}
  if FindResourceW(HInstance, PWideChar(UnicodeString(ResName)), PWideChar(PtrUInt(10))) = 0 then
    Exit(False);
  {$ENDIF}

  try
    ResStr := TResourceStream.Create(HInstance, ResName, PChar(PtrUInt(10)));
  except
    Exit(False);
  end;
  try
    ExpectedSig := ComputeStreamFnv1aHex(ResStr);
    SigPath := TargetFilePath + '.sig';
    if FileExists(TargetFilePath) and FileExists(SigPath) then
    begin
      SL := TStringList.Create;
      try
        SL.LoadFromFile(SigPath);
        if SL.Count > 0 then CurSig := Trim(SL[0]) else CurSig := '';
      finally
        SL.Free;
      end;
      if CurSig = ExpectedSig then
        Exit(True);
    end;

    ForceDirectories(ExtractFileDir(TargetFilePath));
    TmpPath := TargetFilePath + '.tmp';
    Decomp := TDecompressionStream.Create(ResStr, False);
    try
      OutStr := TFileStream.Create(TmpPath, fmCreate);
      try
        repeat
          N := Decomp.Read(Buf[0], SizeOf(Buf));
          if N > 0 then
            OutStr.WriteBuffer(Buf[0], N);
        until N = 0;
      finally
        OutStr.Free;
      end;
    finally
      Decomp.Free;
    end;

    if FileExists(TargetFilePath) then
      SysUtils.DeleteFile(TargetFilePath);
    if not RenameFile(TmpPath, TargetFilePath) then
    begin
      SysUtils.DeleteFile(TmpPath);
      Exit(FileExists(TargetFilePath));
    end;

    SL := TStringList.Create;
    try
      SL.Text := ExpectedSig;
      SL.SaveToFile(SigPath);
    finally
      SL.Free;
    end;
    Result := FileExists(TargetFilePath);
  finally
    ResStr.Free;
  end;
end;

finalization
  UnregisterSingleInstanceWindow;
  ReleaseSingleInstanceLock;

end.
