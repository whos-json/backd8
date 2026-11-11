// Tiny launcher: starts gui.ps1 (next to this exe) with no console window.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class Launcher {
    [STAThread]
    static void Main() {
        string gui = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "gui.ps1");
        if (!File.Exists(gui)) { MessageBox.Show("gui.ps1 not found next to BackD8.exe", "backd8"); return; }
        Process.Start(new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + gui + "\"") {
            UseShellExecute = false, CreateNoWindow = true });
    }
}
