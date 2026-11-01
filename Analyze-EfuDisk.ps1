#requires -Version 5.1
<#
.SYNOPSIS
Fast read-only analysis of Everything .efu exports, including multi-million-row files.
.EXAMPLE
.\Analyze-EfuDisk-Fast.ps1 -Path .\files.efu -Top 30
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [ValidateRange(1,1000)][int]$Top = 30,
    [string]$OutputDir = '',
    [ValidateRange(10000,10000000)][int]$ProgressEvery = 500000
)
$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
if (-not $OutputDir) {
    $OutputDir = Join-Path (Split-Path -Parent $resolved) 'efu-fast-report'
}
[void][System.IO.Directory]::CreateDirectory($OutputDir)
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

$source = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

public static class EfuFastAnalyzer {
    class FolderStat {
        public long Bytes;
        public long FileCount;
    }
    class FileStat {
        public string Path;
        public long Bytes;
        public long Row;
    }
    static readonly StringComparer Comparer = StringComparer.OrdinalIgnoreCase;
    static string Csv(string s) { return "\"" + (s ?? "").Replace("\"", "\"\"") + "\""; }
    static string GiB(long bytes) { return (bytes / 1073741824.0).ToString("N2", CultureInfo.InvariantCulture); }
    // Fast CSV parse of the first two EFU fields. Windows filenames cannot contain newlines.
    // Handles quoted paths, embedded commas and escaped double quotes.
    static bool ParseFirstTwo(string line, out string path, out long bytes) {
        path = null; bytes = 0;
        if (String.IsNullOrEmpty(line)) return false;
        int p = 0, n = line.Length;
        if (line[p] == '"') {
            p++;
            int start = p;
            StringBuilder builder = null;
            while (p < n) {
                if (line[p] == '"') {
                    if (p + 1 < n && line[p+1] == '"') {
                        if (builder == null) builder = new StringBuilder();
                        builder.Append(line, start, p-start);
                        builder.Append('"'); p += 2; start = p;
                        continue;
                    }
                    path = builder == null ? line.Substring(start, p-start) : builder.Append(line, start, p-start).ToString();
                    p++;
                    break;
                }
                p++;
            }
            if (path == null) return false;
            if (p >= n || line[p] != ',') return false;
            p++;
        } else {
            int comma = line.IndexOf(',');
            if (comma <= 0) return false;
            path = line.Substring(0, comma);
            p = comma+1;
        }
        int end = line.IndexOf(',', p);
        if (end < 0) end = n;
        return Int64.TryParse(line.Substring(p,end-p), NumberStyles.Integer, CultureInfo.InvariantCulture, out bytes) && bytes >= 0;
    }
    static void Add(Dictionary<string, FolderStat> dirs, string key, long bytes) {
        FolderStat s;
        if (!dirs.TryGetValue(key, out s)) { s = new FolderStat(); dirs[key] = s; }
        s.Bytes += bytes;
        s.FileCount++;
    }
    static void KeepTop(List<FileStat> files, FileStat entry, int limit) {
        if (files.Count == limit && entry.Bytes <= files[files.Count-1].Bytes) return;
        int lo = 0, hi = files.Count;
        while (lo < hi) {
            int m = lo+(hi-lo)/2;
            if (files[m].Bytes >= entry.Bytes) lo=m+1; else hi=m;
        }
        files.Insert(lo, entry);
        if (files.Count > limit) files.RemoveAt(files.Count-1);
    }
    public static void Run(string source, string output, int top, int progressEvery) {
        var dirs = new Dictionary<string, FolderStat>(Comparer);
        var direct = new Dictionary<string, FolderStat>(Comparer);
        var largest = new List<FileStat>(top);
        long rows = 0, valid = 0, total = 0, errors = 0;
        var started = DateTime.UtcNow;
        using (var reader = new StreamReader(source, Encoding.UTF8, true, 1<<20)) {
            string line = reader.ReadLine();
            if (line == null) throw new InvalidDataException("Empty EFU file");
            if (line.IndexOf("Filename", StringComparison.OrdinalIgnoreCase)<0 || line.IndexOf("Size", StringComparison.OrdinalIgnoreCase)<0)
                throw new InvalidDataException("Header must contain Filename and Size");
            while ((line = reader.ReadLine()) != null) {
                rows++;
                string path; long bytes;
                if (!ParseFirstTwo(line, out path, out bytes) || String.IsNullOrWhiteSpace(path)) { errors++; continue; }
                path = path.Trim().Replace('/', '\\');
                // Standard drive roots only; UNC and non-drive entries are recorded separately.
                string root;
                if (path.Length >= 3 && Char.IsLetter(path[0]) && path[1] == ':' && path[2] == '\\')
                    root = path.Substring(0,3).ToUpperInvariant();
                else if (path.StartsWith("\\\\")) root = "[UNC]";
                else root = "[Other]";
                valid++;
                total += bytes;
                // A directory has an empty or zero-size EFU entry; it cannot be distinguished perfectly
                // without Attributes. Zero-size entries are counted but do not affect totals.
                int last = path.LastIndexOf('\\');
                string parent = last >= 0 ? path.Substring(0,last) : root;
                if (parent.Length == 2 && parent[1] == ':') parent += "\\";
                if (parent.Length == 0) parent = root;
                Add(direct, parent, bytes);
                if (root == "[UNC]" || root == "[Other]") {
                    Add(dirs, root, bytes);
                    Add(dirs, parent, bytes);
                } else {
                    Add(dirs, root, bytes);
                    int pos = 3;
                    while (true) {
                        int idx = path.IndexOf('\\', pos);
                        if (idx < 0 || idx >= last) break;
                        if (idx > 3) Add(dirs, path.Substring(0,idx), bytes);
                        pos = idx+1;
                    }
                    if (parent.Length > 3) Add(dirs, parent, bytes);
                }
                if (largest.Count < top || bytes > largest[largest.Count-1].Bytes)
                    KeepTop(largest, new FileStat {Path=path, Bytes=bytes, Row=rows+1}, top);
                if (progressEvery > 0 && rows % progressEvery == 0)
                    Console.WriteLine("Processed " + rows.ToString("N0",CultureInfo.InvariantCulture) + " rows | " + dirs.Count.ToString("N0",CultureInfo.InvariantCulture) + " folders | " + (DateTime.UtcNow-started).TotalSeconds.ToString("N1",CultureInfo.InvariantCulture)+"s");
            }
        }
        var all = new List<KeyValuePair<string,FolderStat>>(dirs);
        all.Sort((a,b) => b.Value.Bytes.CompareTo(a.Value.Bytes));
        string foldersCsv=Path.Combine(output,"folders-by-size.csv");
        using(var w=new StreamWriter(foldersCsv,false,new UTF8Encoding(true))) {
            w.WriteLine("Folder,InclusiveBytes,InclusiveGiB,FilesBelow,DirectBytes,DirectGiB,DirectFiles");
            foreach(var kv in all) {
                FolderStat d;
                bool has=direct.TryGetValue(kv.Key,out d);
                long directBytes=has?d.Bytes:0, directCount=has?d.FileCount:0;
                w.WriteLine(Csv(kv.Key)+","+kv.Value.Bytes+","+GiB(kv.Value.Bytes)+","+kv.Value.FileCount+","+directBytes+","+GiB(directBytes)+","+directCount);
            }
        }
        string filesCsv=Path.Combine(output,"largest-files.csv");
        using(var w=new StreamWriter(filesCsv,false,new UTF8Encoding(true))) {
            w.WriteLine("Filename,Bytes,GiB,EFURow");
            foreach(var f in largest) w.WriteLine(Csv(f.Path)+","+f.Bytes+","+GiB(f.Bytes)+","+f.Row);
        }
        string summary=Path.Combine(output,"summary.txt");
        using(var w=new StreamWriter(summary,false,new UTF8Encoding(true))) {
            w.WriteLine("EFU file: "+source);
            w.WriteLine("Rows: "+rows+"; valid: "+valid+"; malformed: "+errors);
            w.WriteLine("Logical total of entries: "+GiB(total)+" GiB (not physical disk allocated bytes)");
            w.WriteLine("Distinct folders: "+dirs.Count);
            w.WriteLine("Elapsed: "+(DateTime.UtcNow-started).TotalSeconds.ToString("N1",CultureInfo.InvariantCulture)+" seconds");
            w.WriteLine();
            w.WriteLine("TOP "+top+" FOLDERS (inclusive; nested totals overlap)");
            for(int i=0;i<Math.Min(top,all.Count);i++) w.WriteLine(String.Format(CultureInfo.InvariantCulture,"{0,9:N2} GiB  {1}",all[i].Value.Bytes/1073741824.0,all[i].Key));
            w.WriteLine();
            w.WriteLine("DIRECT ROOT FILES");
            foreach(var root in new [] {"C:\\", "D:\\", "E:\\", "F:\\"}) {
                FolderStat d;
                if(direct.TryGetValue(root,out d)) w.WriteLine(root+"  "+GiB(d.Bytes)+" GiB  "+d.FileCount+" direct entries");
            }
            w.WriteLine();
            w.WriteLine("TOP "+top+" FILES");
            foreach(var f in largest) w.WriteLine(String.Format(CultureInfo.InvariantCulture,"{0,9:N2} GiB  {1}",f.Bytes/1073741824.0,f.Path));
        }
        Console.WriteLine("\nDONE: "+rows.ToString("N0",CultureInfo.InvariantCulture)+" rows, "+GiB(total)+" GiB logical, "+dirs.Count.ToString("N0",CultureInfo.InvariantCulture)+" folders; "+(DateTime.UtcNow-started).TotalSeconds.ToString("N1",CultureInfo.InvariantCulture)+"s");
        Console.WriteLine("\nTop-level breakdown (inclusive):");
        foreach(var root in new [] {"C:\\", "D:\\", "E:\\", "F:\\"}) {
            FolderStat rootStat;
            if(!dirs.TryGetValue(root,out rootStat)) continue;
            Console.WriteLine("\n"+root+"  "+GiB(rootStat.Bytes)+" GiB");
            var children = new List<KeyValuePair<string,FolderStat>>();
            foreach(var kv in dirs) {
                if(kv.Key.Length > root.Length && kv.Key.StartsWith(root,StringComparison.OrdinalIgnoreCase)) {
                    string suffix = kv.Key.Substring(root.Length);
                    if(suffix.IndexOf('\\') < 0) children.Add(kv);
                }
            }
            children.Sort((a,b) => b.Value.Bytes.CompareTo(a.Value.Bytes));
            foreach(var kv in children.GetRange(0,Math.Min(top,children.Count)))
                Console.WriteLine("  "+GiB(kv.Value.Bytes).PadLeft(10)+" GiB  "+kv.Key);
            FolderStat d;
            if(direct.TryGetValue(root,out d)) Console.WriteLine("  "+GiB(d.Bytes).PadLeft(10)+" GiB  [FILES DIRECTLY IN ROOT]");
        }
        Console.WriteLine("\nTop "+top+" non-root folders:");
        int printed=0;
        foreach(var kv in all) {
            if(kv.Key.Length==3 && kv.Key[1]==':') continue;
            Console.WriteLine("  "+GiB(kv.Value.Bytes).PadLeft(10)+" GiB  "+kv.Key);
            if(++printed>=top) break;
        }
        Console.WriteLine("\nReports: "+summary+" | "+foldersCsv+" | "+filesCsv);
    }
}
'@
if (-not ('EfuFastAnalyzer' -as [type])) {
    Write-Host 'Initializing fast CSV analyzer (C#)...'
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
}
Write-Host "Reading $resolved"
[EfuFastAnalyzer]::Run($resolved, $OutputDir, $Top, $ProgressEvery)
