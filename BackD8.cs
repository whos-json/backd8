// Tiny launcher: starts gui.ps1 (next to this exe) with no console window.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class Launcher {
    [STAThread]
    static void Main() {
        string gui = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "gui.ps1");
        if (!File.Exists(gui)) { MessageBox.Show("gui.ps1 not found next to BackD8.exe:\n" + gui, "backd8"); return; }
        try {
            Process p = Process.Start(new ProcessStartInfo("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + gui + "\"") {
                UseShellExecute = false, CreateNoWindow = true });
            if (p == null) MessageBox.Show("powershell.exe could not be started.", "backd8", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        } catch (Exception ex) {
            MessageBox.Show("Could not start powershell.exe:\n" + ex.Message, "backd8", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
