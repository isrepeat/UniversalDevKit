using System;
using System.IO;
using System.Xml.Linq;
using System.Linq;
using System.Text;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Collections.Generic;

using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

namespace UniversalDevKit.WinRT
{
    public sealed class ReadActivationManifest : Task
    {
        [Required] public string WinMD { get; set; }
        [Required] public string DllName { get; set; }
        [Required] public string Output { get; set; }

        public override bool Execute()
        {
            try
            {
                var file = new XElement(ManifestXml.Assembly + "file", new XAttribute("name", DllName));
                using (var stream = File.OpenRead(WinMD))
                using (var pe = new PEReader(stream))
                {
                    var reader = pe.GetMetadataReader();
                    foreach (var handle in reader.TypeDefinitions)
                    {
                        var type = reader.GetTypeDefinition(handle);
                        if ((type.Attributes & TypeAttributes.WindowsRuntime) == 0 ||
                            (type.Attributes & TypeAttributes.VisibilityMask) != TypeAttributes.Public ||
                            (type.Attributes & TypeAttributes.Interface) != 0)
                            continue;

                        var attributes = type.GetCustomAttributes().Select(reader.GetCustomAttribute).ToArray();
                        bool HasAttribute(string name) => attributes.Any(attribute =>
                            GetAttributeName(reader, attribute) == "Windows.Foundation.Metadata." + name);
                        if (!HasAttribute("ActivatableAttribute") && !HasAttribute("StaticAttribute") && !HasAttribute("ComposableAttribute"))
                            continue;

                        string threading = "both";
                        foreach (var attribute in attributes.Where(attribute =>
                            GetAttributeName(reader, attribute) == "Windows.Foundation.Metadata.ThreadingAttribute"))
                        {
                            var blob = reader.GetBlobReader(attribute.Value);
                            if (blob.ReadUInt16() != 1) throw new InvalidDataException("Invalid threading attribute.");
                            switch (blob.ReadInt32())
                            {
                                case 1: threading = "STA"; break;
                                case 2: threading = "MTA"; break;
                                case 3: threading = "both"; break;
                                default: throw new InvalidDataException("Unsupported WinRT threading model.");
                            }
                        }
                        file.Add(new XElement(ManifestXml.WinRT + "activatableClass",
                            new XAttribute("name", reader.GetString(type.Namespace) + "." + reader.GetString(type.Name)),
                            new XAttribute("threadingModel", threading)));
                    }
                }
                ManifestXml.Save(Output, new XDocument(new XElement(ManifestXml.Assembly + "assembly",
                    new XAttribute("manifestVersion", "1.0"), file)));
                return true;
            }
            catch (Exception exception) { Log.LogErrorFromException(exception); return false; }
        }

        private static string GetAttributeName(MetadataReader reader, CustomAttribute attribute)
        {
            EntityHandle parent;
            if (attribute.Constructor.Kind == HandleKind.MemberReference)
                parent = reader.GetMemberReference((MemberReferenceHandle)attribute.Constructor).Parent;
            else if (attribute.Constructor.Kind == HandleKind.MethodDefinition)
                parent = reader.GetMethodDefinition((MethodDefinitionHandle)attribute.Constructor).GetDeclaringType();
            else return "";
            if (parent.Kind == HandleKind.TypeReference)
            {
                var type = reader.GetTypeReference((TypeReferenceHandle)parent);
                return reader.GetString(type.Namespace) + "." + reader.GetString(type.Name);
            }
            if (parent.Kind == HandleKind.TypeDefinition)
            {
                var type = reader.GetTypeDefinition((TypeDefinitionHandle)parent);
                return reader.GetString(type.Namespace) + "." + reader.GetString(type.Name);
            }
            return "";
        }
    }

    public sealed class MergeActivationManifest : Task
    {
        public string BaseManifest { get; set; }
        [Required] public ITaskItem[] Fragments { get; set; }
        [Required] public string Output { get; set; }

        public override bool Execute()
        {
            try
            {
                var document = string.IsNullOrEmpty(BaseManifest)
                    ? new XDocument(new XElement(ManifestXml.Assembly + "assembly", new XAttribute("manifestVersion", "1.0")))
                    : XDocument.Load(BaseManifest, LoadOptions.PreserveWhitespace);
                if (document.Root.Name != ManifestXml.Assembly + "assembly")
                    throw new InvalidDataException("Expected a desktop application manifest.");
                var registrations = new Dictionary<string, string>(StringComparer.Ordinal);
                foreach (var file in ManifestXml.Files(document.Root))
                    foreach (var type in file.Elements(ManifestXml.WinRT + "activatableClass"))
                        registrations.Add((string)type.Attribute("name"), (string)file.Attribute("name"));

                foreach (var fragment in Fragments.Select(item => item.GetMetadata("FullPath")).Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    foreach (var source in ManifestXml.Files(XDocument.Load(fragment).Root))
                    {
                        string dll = (string)source.Attribute("name");
                        var target = ManifestXml.Files(document.Root).FirstOrDefault(file =>
                            string.Equals((string)file.Attribute("name"), dll, StringComparison.OrdinalIgnoreCase));
                        if (target == null) { target = new XElement(ManifestXml.Assembly + "file", new XAttribute("name", dll)); document.Root.Add(target); }
                        foreach (var type in source.Elements(ManifestXml.WinRT + "activatableClass"))
                        {
                            string name = (string)type.Attribute("name");
                            if (registrations.TryGetValue(name, out string existing))
                            {
                                var registration = target.Elements(ManifestXml.WinRT + "activatableClass").FirstOrDefault(item => (string)item.Attribute("name") == name);
                                if (!string.Equals(existing, dll, StringComparison.OrdinalIgnoreCase) || registration == null ||
                                    (string)registration.Attribute("threadingModel") != (string)type.Attribute("threadingModel"))
                                    throw new InvalidDataException("Conflicting WinRT activation registration: " + name);
                                continue;
                            }
                            registrations.Add(name, dll);
                            target.Add(new XElement(type));
                        }
                    }
                }
                ManifestXml.Save(Output, document);
                return true;
            }
            catch (Exception exception) { Log.LogErrorFromException(exception); return false; }
        }
    }

    internal static class ManifestXml
    {
        internal static readonly XNamespace Assembly = "urn:schemas-microsoft-com:asm.v1";
        internal static readonly XNamespace WinRT = "urn:schemas-microsoft-com:winrt.v1";

        internal static IEnumerable<XElement> Files(XElement root)
        {
            return root.Elements().Where(element => element.Name.LocalName == "file" &&
                (element.Name.Namespace == Assembly || element.Name.NamespaceName == "urn:schemas-microsoft-com:asm.v3"));
        }

        internal static void Save(string path, XDocument document)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));
            string content = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!-- Generated by ProjectTools WinRT manifest tasks. Edit the source manifest or IDL. -->\n" + document.ToString();
            if (!File.Exists(path) || File.ReadAllText(path) != content)
                File.WriteAllText(path, content, new UTF8Encoding(false));
        }
    }
}