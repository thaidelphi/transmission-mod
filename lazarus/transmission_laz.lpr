{******************************************************************************
 * ไฟล์: transmission_laz.lpr
 * โปรเจกต์: Transmission BitTorrent Client (Lazarus / FreePascal Edition)
 * คำอธิบาย:
 *   จุดเริ่มต้นการทำงานหลักของโปรแกรม (Main Program Entry Point)
 *   ทำหน้าที่โหลดทรัพยากรของฟอร์ม, ตั้งค่าการปรับขนาดตาม DPI หน้าจอ (High-DPI Scaling),
 *   สร้างหน้าต่างหลัก (TMainForm) และเริ่มต้น Message Loop ของระบบปฏิบัติการ
 ******************************************************************************}
program transmission_laz;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // โหลด LCL Widgetset สำหรับแพลตฟอร์มปัจจุบัน (Win32/Win64 GDI)
  Forms, uMain, uTypes;

{$R *.res}

begin
  // บังคับใช้ทรัพยากรฟอร์ม (.lfm) ของยูนิตที่เกี่ยวข้อง
  RequireDerivedFormResource := True;

  // เปิดใช้งานการปรับสเกลอัตโนมัติตามค่า DPI ของหน้าจอ Windows
  Application.Scaled := True;

  // กำหนดชื่อแอปพลิเคชันที่แสดงบน Taskbar และ Dialog
  Application.Title := 'Transmission';

  // เริ่มต้นระบบ LCL (Lazarus Component Library)
  Application.Initialize;

  // สร้างอินสแตนซ์หน้าต่างหลักของโปรแกรม (TMainForm จากยูนิต uMain)
  Application.CreateForm(TMainForm, MainForm);

  // หากเปิดด้วยพารามิเตอร์ --minimized (เช่น จาก Auto-start ของ Windows) ให้ซ่อนหน้าต่างลง System Tray ทันที
  if HasCliFlag('--minimized') then
  begin
    Application.ShowMainForm := False;
    MainForm.Visible := False;
  end;

  // เข้าสู่ Event Loop หลักของโปรแกรมจนกว่าผู้ใช้จะสั่งปิดโปรแกรม
  Application.Run;
end.
