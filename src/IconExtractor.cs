using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;

namespace IconTools
{
    public enum ExportFormat
    {
        Ico,
        Png,
        All
    }

    public class IconGroupInfo
    {
        public string Name { get; set; } = string.Empty;
        public ushort? Id { get; set; }
        public bool IsNamed => Id == null;
        public int ImageCount { get; set; }
        public string Sizes { get; set; } = string.Empty;
        public string MaxResolution { get; set; } = string.Empty;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    internal struct GRPICONDIR
    {
        public ushort idReserved;
        public ushort idType;
        public ushort idCount;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    internal struct GRPICONDIRENTRY
    {
        public byte bWidth;
        public byte bHeight;
        public byte bColorCount;
        public byte bReserved;
        public ushort wPlanes;
        public ushort wBitCount;
        public uint dwBytesInRes;
        public ushort nID;
    }

    public static class IconExtractor
    {
        private static class NativeMethods
        {
            public const uint LOAD_LIBRARY_AS_DATAFILE = 0x00000002;
            public const uint LOAD_LIBRARY_AS_IMAGE_RESOURCE = 0x00000020;
            public const int ERROR_RESOURCE_TYPE_NOT_FOUND = 1813;

            public static readonly IntPtr RT_ICON = (IntPtr)3;
            public static readonly IntPtr RT_GROUP_ICON = (IntPtr)14;

            public delegate bool EnumResNameProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, IntPtr lParam);

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "LoadLibraryExW", SetLastError = true)]
            public static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hFile, uint dwFlags);

            [DllImport("kernel32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool FreeLibrary(IntPtr hModule);

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "EnumResourceNamesW", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool EnumResourceNames(IntPtr hModule, IntPtr lpszType, EnumResNameProc lpEnumFunc, IntPtr lParam);

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "FindResourceW", SetLastError = true)]
            public static extern IntPtr FindResource(IntPtr hModule, IntPtr lpName, IntPtr lpType);

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern IntPtr LoadResource(IntPtr hModule, IntPtr hResInfo);

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern IntPtr LockResource(IntPtr hResData);

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern uint SizeofResource(IntPtr hModule, IntPtr hResInfo);
        }

        public static List<IconGroupInfo> GetIconGroups(string filePath)
        {
            if (!File.Exists(filePath))
            {
                throw new FileNotFoundException("The specified file was not found.", filePath);
            }

            IntPtr hModule = NativeMethods.LoadLibraryEx(filePath, IntPtr.Zero, NativeMethods.LOAD_LIBRARY_AS_DATAFILE | NativeMethods.LOAD_LIBRARY_AS_IMAGE_RESOURCE);
            if (hModule == IntPtr.Zero)
            {
                int lastError = Marshal.GetLastWin32Error();
                // 193 is ERROR_BAD_EXE_FORMAT (not a valid PE)
                // 1157 is ERROR_DLL_INIT_FAILED (or other DLL loading error)
                // 1812 is ERROR_RESOURCE_DATA_NOT_FOUND
                // 1813 is ERROR_RESOURCE_TYPE_NOT_FOUND
                if (lastError == 193 || lastError == 1157 || lastError == 1812 || lastError == 1813)
                {
                    return new List<IconGroupInfo>();
                }
                throw new System.ComponentModel.Win32Exception(lastError, $"Failed to load library '{filePath}'.");
            }

            var groups = new List<IconGroupInfo>();

            try
            {
                NativeMethods.EnumResNameProc callback = (IntPtr h, IntPtr type, IntPtr name, IntPtr param) =>
                {
                    string resName;
                    ushort? resId = null;

                    if (((ulong)name >> 16) == 0)
                    {
                        ushort id = (ushort)name.ToInt32();
                        resName = $"#{id}";
                        resId = id;
                    }
                    else
                    {
                        resName = Marshal.PtrToStringUni(name) ?? string.Empty;
                    }

                    var groupInfo = GetGroupInfo(hModule, name, resName, resId);
                    if (groupInfo != null)
                    {
                        groups.Add(groupInfo);
                    }

                    return true;
                };

                bool result = NativeMethods.EnumResourceNames(hModule, NativeMethods.RT_GROUP_ICON, callback, IntPtr.Zero);
                int lastError = Marshal.GetLastWin32Error();
                if (!result && lastError != NativeMethods.ERROR_RESOURCE_TYPE_NOT_FOUND)
                {
                    // Ignore or throw on unexpected enumeration failures
                }
            }
            finally
            {
                NativeMethods.FreeLibrary(hModule);
            }

            return groups;
        }

        private static IconGroupInfo? GetGroupInfo(IntPtr hModule, IntPtr namePtr, string resName, ushort? resId)
        {
            IntPtr hResInfo = NativeMethods.FindResource(hModule, namePtr, NativeMethods.RT_GROUP_ICON);
            if (hResInfo == IntPtr.Zero) return null;

            IntPtr hResData = NativeMethods.LoadResource(hModule, hResInfo);
            if (hResData == IntPtr.Zero) return null;

            IntPtr pResData = NativeMethods.LockResource(hResData);
            if (pResData == IntPtr.Zero) return null;

            GRPICONDIR header = Marshal.PtrToStructure<GRPICONDIR>(pResData);
            
            var sizes = new List<string>();
            int maxRes = 0;
            string maxResStr = "0x0";

            IntPtr pEntry = pResData + 6;
            for (int i = 0; i < header.idCount; i++)
            {
                var entry = Marshal.PtrToStructure<GRPICONDIRENTRY>(pEntry + (i * 14));
                int w = entry.bWidth == 0 ? 256 : entry.bWidth;
                int h = entry.bHeight == 0 ? 256 : entry.bHeight;
                sizes.Add($"{w}x{h}");

                if (w > maxRes)
                {
                    maxRes = w;
                    maxResStr = $"{w}x{h}";
                }
            }

            return new IconGroupInfo
            {
                Name = resName,
                Id = resId,
                ImageCount = header.idCount,
                Sizes = string.Join(", ", sizes),
                MaxResolution = maxResStr
            };
        }

        public static byte[] ReconstructIcoBytes(string filePath, string resourceName)
        {
            if (!File.Exists(filePath))
            {
                throw new FileNotFoundException("The specified file was not found.", filePath);
            }

            IntPtr hModule = NativeMethods.LoadLibraryEx(filePath, IntPtr.Zero, NativeMethods.LOAD_LIBRARY_AS_DATAFILE | NativeMethods.LOAD_LIBRARY_AS_IMAGE_RESOURCE);
            if (hModule == IntPtr.Zero)
            {
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), $"Failed to load library '{filePath}'.");
            }

            IntPtr namePtr = IntPtr.Zero;
            try
            {
                if (resourceName.StartsWith("#") && ushort.TryParse(resourceName.Substring(1), out ushort id))
                {
                    namePtr = (IntPtr)id;
                }
                else
                {
                    namePtr = Marshal.StringToHGlobalUni(resourceName);
                }

                IntPtr hResInfo = NativeMethods.FindResource(hModule, namePtr, NativeMethods.RT_GROUP_ICON);
                if (hResInfo == IntPtr.Zero)
                {
                    throw new Exception($"Failed to find RT_GROUP_ICON resource '{resourceName}'.");
                }

                IntPtr hResData = NativeMethods.LoadResource(hModule, hResInfo);
                IntPtr pResData = NativeMethods.LockResource(hResData);
                GRPICONDIR header = Marshal.PtrToStructure<GRPICONDIR>(pResData);

                var entries = new GRPICONDIRENTRY[header.idCount];
                IntPtr pEntry = pResData + 6;
                for (int i = 0; i < header.idCount; i++)
                {
                    entries[i] = Marshal.PtrToStructure<GRPICONDIRENTRY>(pEntry + (i * 14));
                }

                using (var ms = new MemoryStream())
                using (var bw = new BinaryWriter(ms))
                {
                    bw.Write(header.idReserved);
                    bw.Write(header.idType);
                    bw.Write(header.idCount);

                    int imageOffset = 6 + (header.idCount * 16);

                    for (int i = 0; i < header.idCount; i++)
                    {
                        var entry = entries[i];
                        bw.Write(entry.bWidth);
                        bw.Write(entry.bHeight);
                        bw.Write(entry.bColorCount);
                        bw.Write(entry.bReserved);
                        bw.Write(entry.wPlanes);
                        bw.Write(entry.wBitCount);
                        bw.Write(entry.dwBytesInRes);
                        bw.Write((uint)imageOffset);

                        imageOffset += (int)entry.dwBytesInRes;
                    }

                    for (int i = 0; i < header.idCount; i++)
                    {
                        var entry = entries[i];
                        IntPtr iconResInfo = NativeMethods.FindResource(hModule, (IntPtr)entry.nID, NativeMethods.RT_ICON);
                        if (iconResInfo == IntPtr.Zero)
                        {
                            throw new Exception($"Failed to find RT_ICON resource with ID {entry.nID}.");
                        }

                        IntPtr iconResData = NativeMethods.LoadResource(hModule, iconResInfo);
                        IntPtr pIconData = NativeMethods.LockResource(iconResData);
                        uint iconSize = NativeMethods.SizeofResource(hModule, iconResInfo);

                        byte[] iconBytes = new byte[iconSize];
                        Marshal.Copy(pIconData, iconBytes, 0, (int)iconSize);

                        bw.Write(iconBytes);
                    }

                    return ms.ToArray();
                }
            }
            finally
            {
                if (namePtr != IntPtr.Zero && ((ulong)namePtr >> 16) != 0)
                {
                    Marshal.FreeHGlobal(namePtr);
                }
                NativeMethods.FreeLibrary(hModule);
            }
        }

        public static void ExtractIcon(string filePath, string resourceName, string outputPath, ExportFormat format)
        {
            byte[] icoBytes = ReconstructIcoBytes(filePath, resourceName);

            if (format == ExportFormat.Ico || format == ExportFormat.All)
            {
                string? dir = Path.GetDirectoryName(outputPath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                File.WriteAllBytes(outputPath, icoBytes);
            }

            if (format == ExportFormat.Png || format == ExportFormat.All)
            {
                string dir = Path.GetDirectoryName(outputPath) ?? string.Empty;
                string nameWithoutExt = Path.GetFileNameWithoutExtension(outputPath);
                string basePngPath = Path.Combine(dir, nameWithoutExt);
                
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                SaveIcoAsPngs(icoBytes, basePngPath);
            }
        }

        private static void SaveIcoAsPngs(byte[] icoBytes, string baseOutputPath)
        {
            using (var ms = new MemoryStream(icoBytes))
            {
                var decoder = new IconBitmapDecoder(
                    ms,
                    BitmapCreateOptions.PreservePixelFormat,
                    BitmapCacheOption.OnLoad);

                for (int i = 0; i < decoder.Frames.Count; i++)
                {
                    BitmapFrame frame = decoder.Frames[i];
                    int width = frame.PixelWidth;
                    int height = frame.PixelHeight;
                    string outputPath = $"{baseOutputPath}_{width}x{height}.png";

                    var encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(frame);

                    using (var fs = new FileStream(outputPath, FileMode.Create, FileAccess.Write))
                    {
                        encoder.Save(fs);
                    }
                }
            }
        }

        public static void CreateIconFromPngs(string[] pngPaths, string outputPath)
        {
            if (pngPaths == null || pngPaths.Length == 0)
            {
                throw new ArgumentException("At least one PNG path must be provided.", nameof(pngPaths));
            }

            string? dir = Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            using (var fs = new FileStream(outputPath, FileMode.Create, FileAccess.Write))
            using (var bw = new BinaryWriter(fs))
            {
                bw.Write((ushort)0); // Reserved
                bw.Write((ushort)1); // Type: 1 = Icon
                bw.Write((ushort)pngPaths.Length);

                int offset = 6 + (pngPaths.Length * 16);
                var imgData = new List<byte[]>();

                foreach (var path in pngPaths)
                {
                    if (!File.Exists(path))
                    {
                        throw new FileNotFoundException($"PNG file not found: {path}");
                    }

                    byte[] bytes = File.ReadAllBytes(path);
                    imgData.Add(bytes);

                    int width = 0;
                    int height = 0;

                    // Parse PNG width/height from IHDR header directly if possible
                    if (bytes.Length > 24 &&
                        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
                        bytes[12] == 0x49 && bytes[13] == 0x48 && bytes[14] == 0x44 && bytes[15] == 0x52)
                    {
                        width = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
                        height = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
                    }
                    else
                    {
                        // Fallback using WPF BitmapDecoder
                        using (var pngMs = new MemoryStream(bytes))
                        {
                            var decoder = BitmapDecoder.Create(pngMs, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                            width = decoder.Frames[0].PixelWidth;
                            height = decoder.Frames[0].PixelHeight;
                        }
                    }

                    bw.Write((byte)(width >= 256 ? 0 : width));
                    bw.Write((byte)(height >= 256 ? 0 : height));
                    bw.Write((byte)0); // bColorCount
                    bw.Write((byte)0); // bReserved
                    bw.Write((ushort)1); // wPlanes
                    bw.Write((ushort)32); // wBitCount
                    bw.Write((uint)bytes.Length);
                    bw.Write((uint)offset);

                    offset += bytes.Length;
                }

                foreach (var data in imgData)
                {
                    bw.Write(data);
                }
            }
        }
    }
}
