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
  Classes, SysUtils, Math;

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

end.
