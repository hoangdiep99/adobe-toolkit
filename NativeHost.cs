using System;
using System.IO;
using System.IO.Compression;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Adobe Toolkit")]
[assembly: AssemblyDescription("Adobe Diagnostic & Clean Utility for Windows")]
[assembly: AssemblyCompany("HoangDiep Tools")]
[assembly: AssemblyProduct("Adobe Toolkit")]
[assembly: AssemblyCopyright("Copyright (c) 2026 HoangDiep")]
[assembly: AssemblyVersion("0.5.0.0")]
[assembly: AssemblyFileVersion("0.5.0.0")]
[assembly: ComVisible(false)]

public static class AdobeWin32Cred {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite([In] ref CREDENTIAL userCredential, [In] uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
    private static extern void CredFree([In] IntPtr cred);

    public static bool DeleteTarget(string target) {
        bool ok = false;
        uint[] types = new uint[] { 1, 2, 3, 4 };
        foreach (uint t in types) {
            if (CredDelete(target, t, 0)) ok = true;
            if (CredDelete("LegacyGeneric:target=" + target, t, 0)) ok = true;
        }
        return ok;
    }

    public static string ExportTargetBase64(string target) {
        IntPtr ptr = IntPtr.Zero;
        uint foundType = 1;
        bool readOk = false;
        foreach (uint t in new uint[] { 1, 2, 3, 4 }) {
            if (CredRead(target, t, 0, out ptr)) { foundType = t; readOk = true; break; }
        }
        if (!readOk || ptr == IntPtr.Zero) return null;
        try {
            CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(ptr, typeof(CREDENTIAL));
            byte[] blob = new byte[c.CredentialBlobSize];
            if (c.CredentialBlobSize > 0 && c.CredentialBlob != IntPtr.Zero) {
                Marshal.Copy(c.CredentialBlob, blob, 0, (int)c.CredentialBlobSize);
            }
            string u = c.UserName ?? "";
            return foundType.ToString() + "|" + c.Persist.ToString() + "|" + Convert.ToBase64String(Encoding.UTF8.GetBytes(u)) + "|" + Convert.ToBase64String(blob);
        } finally {
            CredFree(ptr);
        }
    }

    public static bool RestoreTargetBase64(string target, string packed) {
        if (string.IsNullOrEmpty(packed)) return false;
        string[] parts = packed.Split('|');
        if (parts.Length < 4) return false;
        uint type = uint.Parse(parts[0]);
        uint persist = uint.Parse(parts[1]);
        string user = Encoding.UTF8.GetString(Convert.FromBase64String(parts[2]));
        byte[] blob = Convert.FromBase64String(parts[3]);
        IntPtr blobPtr = IntPtr.Zero;
        try {
            if (blob.Length > 0) {
                blobPtr = Marshal.AllocHGlobal(blob.Length);
                Marshal.Copy(blob, 0, blobPtr, blob.Length);
            }
            CREDENTIAL c = new CREDENTIAL();
            c.Type = type;
            c.TargetName = target;
            c.Persist = persist;
            c.UserName = string.IsNullOrEmpty(user) ? null : user;
            c.CredentialBlobSize = (uint)blob.Length;
            c.CredentialBlob = blobPtr;
            return CredWrite(ref c, 0);
        } finally {
            if (blobPtr != IntPtr.Zero) Marshal.FreeHGlobal(blobPtr);
        }
    }
}

public static class AdobeTaskbarAppId {
    [DllImport("shell32.dll", SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);
}

internal static class Program {
    [STAThread]
    private static int Main(string[] args) {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        try {
            string scriptText;
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream s = asm.GetManifestResourceStream("AdobeToolkit.Payload.gz")) {
                if (s == null) {
                    MessageBox.Show("Embedded payload not found.", "Adobe Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return 1;
                }
                using (GZipStream gz = new GZipStream(s, CompressionMode.Decompress))
                using (StreamReader sr = new StreamReader(gz, Encoding.UTF8)) {
                    scriptText = sr.ReadToEnd();
                }
            }

            InitialSessionState iss = InitialSessionState.CreateDefault();
            iss.ApartmentState = System.Threading.ApartmentState.STA;
            iss.ThreadOptions = PSThreadOptions.UseCurrentThread;
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss)) {
                rs.Open();
                Runspace.DefaultRunspace = rs;
                using (PowerShell ps = PowerShell.Create()) {
                    ps.Runspace = rs;
                    ps.AddScript(scriptText);
                    ps.Invoke();
                    if (ps.HadErrors && ps.Streams.Error.Count > 0) {
                        MessageBox.Show(ps.Streams.Error[0].Exception.Message, "Adobe Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return 1;
                    }
                }
            }
            return 0;
        } catch (Exception ex) {
            MessageBox.Show(ex.Message, "Adobe Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
