using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Reflection;

namespace AndroidAppPreviewerPluginSDK {
    public enum NativeCommandType {
        BeginClip,
        EndClip,
        Outline,
        RoundedRect,
        RoundedRectOutline,
        Text,
        Image
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct NativeRect {
        public float X;
        public float Y;
        public float Width;
        public float Height;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct NativeInspectionResult {
        public int Line;
        public int Column;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 1024)]
        public string SourcePath;
        public NativeRect Bounds;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct NativeColor {
        public float Red;
        public float Green;
        public float Blue;
        public float Alpha;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct NativeInteractionResult {
        public int Kind;
        public int Direction;
        public IntPtr Target;
        public int ItemIndex;
    }

    [StructLayout(LayoutKind.Sequential)]
    public unsafe struct NativeCommand {
        public int Type;
        public NativeRect Bounds;
        public NativeColor Color;
        public float Value;
        public fixed byte Text[512];
        public fixed byte Auxiliary[128];

        public string GetText() {
            fixed (byte* value = this.Text) {
                return NativeCommand.ReadUtf8(value, 512);
            }
        }

        public string GetAuxiliary() {
            fixed (byte* value = this.Auxiliary) {
                return NativeCommand.ReadUtf8(value, 128);
            }
        }

        public float GetAuxiliaryFloat() {
            fixed (byte* value = this.Auxiliary) {
                return *(float*)value;
            }
        }

        private static string ReadUtf8(byte* value, int capacity) {
            var length = 0;
            while (length < capacity && value[length] != 0) {
                ++length;
            }

            return Encoding.UTF8.GetString(value, length);
        }
    }

    public static class NativeRuntime {
        private const uint PluginAbiVersion = 1;
        private const uint PluginAbiTableVersion = 1;
        private static string? pluginPath;
        private static class Delegates {
            //
            // Загрузка корневой ABI-таблицы и разрешение её function pointers.
            //
            public static class Abi {
                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_get_abi(uint requestedVersion);

            }

            //
            // Метаданные плагина и навигация.
            //
            public static class Metadata {
                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate uint xp_get_abi_version();

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_get_navigation_graph(IntPtr session, [Out] byte[] graphJson, int capacity);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_get_plugin_info([Out] byte[] pluginInfoJson, int capacity);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_get_initial_page_id(IntPtr session, [Out] byte[] pageId, int capacity);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_navigate(IntPtr session, [MarshalAs(UnmanagedType.LPUTF8Str)] string transitionIds);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_last_error();
            }

            //
            // Жизненный цикл preview-сессии, сценарии, ввод и inspection.
            //
            public static class Session {
                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_create_session(int width, int height);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate void xp_destroy_session(IntPtr session);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_load_page(IntPtr session, [MarshalAs(UnmanagedType.LPUTF8Str)] string page);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_current_page(IntPtr session, [Out] byte[] page, int capacity);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_is_transitioning(IntPtr session);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_navigate_preview_route(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string target);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_navigate_preview_route_path(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string path);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_preview_route_graph(IntPtr session, [Out] StringBuilder graph, int capacity);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_preview_page_title(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string page,
                    [Out] byte[] title,
                    int capacity);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_apply_preview_scenario(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string page,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string json);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_export_preview_state(IntPtr session);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_can_save_preview_state(IntPtr session);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_reload_markup(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string page,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string markup,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string sourcePath);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_resize(IntPtr session, int width, int height);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_set_animation_playback_rate(IntPtr session, float value);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_pointer_down(IntPtr session, float x, float y);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_pointer_move(IntPtr session, float x, float y);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_pointer_up(IntPtr session, float x, float y);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_pointer_cancel(IntPtr session);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_cursor_kind(IntPtr session, float x, float y);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_inspect(IntPtr session, float x, float y, out NativeInspectionResult result);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_set_inspection_wireframe(
                    IntPtr session,
                    float thickness,
                    int lineStyle,
                    NativeColor color,
                    NativeColor marginColor,
                    NativeColor paddingColor);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_set_selected_wireframe(
                    IntPtr session,
                    float thickness,
                    int lineStyle,
                    NativeColor color,
                    NativeColor marginColor,
                    NativeColor paddingColor);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_clear_inspection_wireframe(IntPtr session);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_clear_selected_inspection_element(IntPtr session);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_select_inspection_element(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string sourcePath,
                    int line,
                    int column);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_pin_inspection_element(IntPtr session);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_update(IntPtr session);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_session_render_angle_surface(IntPtr session, IntPtr surface, [Out] byte[] pixels, int stride, int capacity);
            }

            //
            // Создание, поиск, layout и геометрия XAML-элементов.
            //
            public static class Element {
                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_create_element([MarshalAs(UnmanagedType.LPUTF8Str)] string type);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate void xp_destroy_element(IntPtr element);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_items_remove_item(IntPtr target);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_add_child(IntPtr parent, IntPtr child);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_set_attribute(
                    IntPtr element,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string name,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string value);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_find_element(
                    IntPtr root,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string id);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_layout(IntPtr root, float width, float height);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_hit_test(IntPtr root, float x, float y);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_hit_test_visual(IntPtr root, float x, float y);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_hit_test_cursor_kind(IntPtr root, float x, float y);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_element_bounds(IntPtr element, out NativeRect bounds);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_scroll_by(IntPtr root, float x, float y, float horizontalDelta, float verticalDelta);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_element_id(IntPtr element);
            }

            //
            // Взаимодействие, scrolling, animation и visual states.
            //
            public static class Interaction {
                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_add_storyboard_animation(IntPtr element, int trigger,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string? name,
                    [In] IntPtr[] keys, [In] IntPtr[] values, int count);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_attach_animations(IntPtr root, IntPtr animations);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_set_page_transition(
                    IntPtr root,
                    IntPtr animations,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string from,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string to,
                    int backward,
                    int visible);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_add_storyboard_track(
                    IntPtr element,
                    int trigger,
                    int property,
                    float from,
                    float to,
                    int durationMilliseconds,
                    int easing);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_add_visual_state_track(
                    IntPtr scope,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string groupName,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string stateName,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string targetName,
                    int property, float from, float to, int durationMilliseconds, int easing);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_go_to_visual_state(
                    IntPtr scope,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string groupName,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string stateName,
                    int useTransitions);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_scroll_begin(IntPtr root, IntPtr animations, float x, float y);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_scroll_drag(IntPtr animations, float verticalDelta);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate void xp_scroll_end(IntPtr animations);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_set_render_offset_x(IntPtr element, float value);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_animate_render_offset_x(
                    IntPtr element,
                    IntPtr animations,
                    float value,
                    int durationMilliseconds);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_handle_tap(IntPtr element, IntPtr animations);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_handle_pointer_down(IntPtr element, IntPtr animations);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_handle_pointer_up(IntPtr element, IntPtr animations);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_create_animation_controller();

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate void xp_destroy_animation_controller(IntPtr animations);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_create_interaction_controller();

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate void xp_destroy_interaction_controller(IntPtr controller);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_interaction_pointer_down(
                    IntPtr controller, IntPtr root, IntPtr animations, float x, float y);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_interaction_pointer_move(IntPtr controller, float x, float y);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_interaction_pointer_up(
                    IntPtr controller, IntPtr root, IntPtr animations, float x, float y, out NativeInteractionResult result);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_interaction_scroll_wheel(
                    IntPtr controller, IntPtr root, float x, float y, float horizontalDelta, float verticalDelta);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_interaction_update(IntPtr controller);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_set_animation_playback_rate(IntPtr animations, float playbackRate);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_update_animations(IntPtr animations);
            }

            //
            // ANGLE surface и запись результата rendering.
            //
            public static class Rendering {
                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_create_angle_surface(
                    int width,
                    int height,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string fontPath,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string resourceRoot);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate void xp_destroy_angle_surface(IntPtr surface);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_render_angle_surface(
                    IntPtr surface,
                    IntPtr root,
                    [Out] byte[] pixels,
                    int stride,
                    int capacity);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_render(IntPtr root, [Out] NativeCommand[]? commands, int capacity);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_render_angle(
                    IntPtr root,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string fontPath,
                    int width,
                    int height,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string resourceRoot,
                    [Out] byte[] pixels,
                    int stride,
                    int capacity);
            }

            //
            // Completion для поддерживаемых элементов и атрибутов.
            //
            public static class XamlCompletion
            {
                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_xaml_supported_attribute_count(
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string elementType);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_xaml_supported_attribute_name(
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string elementType,
                    int index);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate int xp_xaml_supported_element_count();

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate IntPtr xp_xaml_supported_element_name(int index);
            }

            //
            // Настройка и отправка логов.
            //
            public static class Logging {
                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate void xp_configure_logging([MarshalAs(UnmanagedType.LPUTF8Str)] string filePath);

                [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
                public delegate void xp_log_info([MarshalAs(UnmanagedType.LPUTF8Str)] string message);
            }

        }
        private static IntPtr pluginHandle;


        [StructLayout(LayoutKind.Sequential)]
        private struct NativeAbiTable {
            public uint Version;
            public uint Size;
            public IntPtr[] FunctionPointers;
        }

        private static readonly Dictionary<string, IntPtr> functionPointers = new(StringComparer.Ordinal);

        private static T Get<T>(string name) where T : Delegate {
            if (!NativeRuntime.functionPointers.TryGetValue(name, out var functionPointer) || functionPointer == IntPtr.Zero) {
                throw new MissingMethodException($"Preview-plugin не предоставляет ABI-функцию {name}.");
            }
            return Marshal.GetDelegateForFunctionPointer<T>(functionPointer);
        }

        private static void AddFunctions(NativeAbiTable table, string tableName, params string[] names) {
            if (table.Version != NativeRuntime.PluginAbiTableVersion || table.Size < sizeof(uint) * 2 + IntPtr.Size * names.Length ||
                table.FunctionPointers == null || table.FunctionPointers.Length < names.Length) {
                throw new InvalidOperationException($"Preview-plugin вернул неполную ABI-таблицу {tableName}.");
            }
            for (var index = 0; index < names.Length; ++index) {
                NativeRuntime.functionPointers.Add(names[index], table.FunctionPointers[index]);
            }
        }

        public static void ConfigurePlugin(string? path) {
            if (string.IsNullOrWhiteSpace(path)) return;
            var fullPath = Path.GetFullPath(path);
            if (!File.Exists(fullPath)) throw new FileNotFoundException("Не найдена DLL preview-plugin.", fullPath);
            if (NativeRuntime.pluginHandle != IntPtr.Zero && !string.Equals(NativeRuntime.pluginPath, fullPath, StringComparison.OrdinalIgnoreCase)) {
                throw new InvalidOperationException("Нельзя заменить preview-plugin, пока загруженная DLL участвует в ABI-сеансе.");
            }
            NativeRuntime.pluginPath = fullPath;
            NativeRuntime.pluginHandle = NativeLibrary.Load(fullPath);
            NativeRuntime.LoadAbi(NativeRuntime.pluginHandle);
        }

        private static void LoadAbi(IntPtr libraryHandle) {
            var fnGetAbiAddress = NativeLibrary.GetExport(libraryHandle, "xp_get_abi");
            var fnGetAbi = Marshal.GetDelegateForFunctionPointer<Delegates.Abi.xp_get_abi>(fnGetAbiAddress);
            var fnAbiAddress = fnGetAbi(NativeRuntime.PluginAbiTableVersion);
            if (fnAbiAddress == IntPtr.Zero) throw new InvalidOperationException("Preview-plugin не поддерживает запрошенную таблицу ABI v1.");
            var rootVersion = (uint)Marshal.ReadInt32(fnAbiAddress);
            var rootSize = (uint)Marshal.ReadInt32(fnAbiAddress, sizeof(uint));
            if (rootVersion != NativeRuntime.PluginAbiTableVersion) {
                throw new InvalidOperationException("Preview-plugin вернул неполную корневую таблицу ABI v1.");
            }

            var tableAddress = IntPtr.Add(fnAbiAddress, sizeof(uint) * 2);
            var metadata = NativeRuntime.ReadTable(tableAddress, 6);
            tableAddress = IntPtr.Add(tableAddress, (int)metadata.Size);
            var session = NativeRuntime.ReadTable(tableAddress, 30);
            tableAddress = IntPtr.Add(tableAddress, (int)session.Size);
            var element = NativeRuntime.ReadTable(tableAddress, 17);
            tableAddress = IntPtr.Add(tableAddress, (int)element.Size);
            var interaction = NativeRuntime.ReadTable(tableAddress, 25);
            tableAddress = IntPtr.Add(tableAddress, (int)interaction.Size);
            var rendering = NativeRuntime.ReadTable(tableAddress, 5);
            tableAddress = IntPtr.Add(tableAddress, (int)rendering.Size);
            var xamlCompletion = NativeRuntime.ReadTable(tableAddress, 4);
            tableAddress = IntPtr.Add(tableAddress, (int)xamlCompletion.Size);
            var logging = NativeRuntime.ReadTable(tableAddress, 2);
            if (rootSize < tableAddress.ToInt64() - fnAbiAddress.ToInt64() + logging.Size) {
                throw new InvalidOperationException("Preview-plugin вернул неполную корневую таблицу ABI v1.");
            }
            NativeRuntime.functionPointers.Clear();
            NativeRuntime.AddFunctions(metadata, "metadata", "xp_get_abi_version", "xp_last_error", "xp_get_plugin_info", "xp_get_initial_page_id", "xp_get_navigation_graph", "xp_navigate");
            NativeRuntime.AddFunctions(session, "session", "xp_create_session", "xp_destroy_session", "xp_session_load_page", "xp_session_current_page", "xp_session_is_transitioning", "xp_session_navigate_preview_route", "xp_session_navigate_preview_route_path", "xp_session_preview_route_graph", "xp_session_preview_page_title", "xp_session_apply_preview_scenario", "xp_session_export_preview_state", "xp_session_can_save_preview_state", "xp_session_reload_markup", "xp_session_resize", "xp_session_set_animation_playback_rate", "xp_session_set_status", "xp_session_pointer_down", "xp_session_pointer_move", "xp_session_pointer_up", "xp_session_pointer_cancel", "xp_session_cursor_kind", "xp_session_inspect", "xp_session_set_inspection_wireframe", "xp_session_set_selected_wireframe", "xp_session_clear_inspection_wireframe", "xp_session_clear_selected_inspection_element", "xp_session_select_inspection_element", "xp_session_pin_inspection_element", "xp_session_update", "xp_session_render_angle_surface");
            NativeRuntime.AddFunctions(element, "element", "xp_create_element", "xp_destroy_element", "xp_items_remove_item", "xp_add_child", "xp_set_attribute", "xp_find_element", "xp_find_element_count", "xp_find_element_at", "xp_layout", "xp_hit_test", "xp_hit_test_visual", "xp_hit_test_cursor_kind", "xp_element_bounds", "xp_element_id", "xp_get_scroll_offsets", "xp_set_scroll_offsets", "xp_scroll_by");
            NativeRuntime.AddFunctions(interaction, "interaction", "xp_add_storyboard_animation", "xp_attach_animations", "xp_set_page_transition", "xp_add_storyboard_track", "xp_add_visual_state_track", "xp_go_to_visual_state", "xp_scroll_begin", "xp_scroll_drag", "xp_scroll_end", "xp_set_render_offset_x", "xp_animate_render_offset_x", "xp_handle_tap", "xp_handle_pointer_down", "xp_handle_pointer_up", "xp_create_animation_controller", "xp_destroy_animation_controller", "xp_create_interaction_controller", "xp_destroy_interaction_controller", "xp_interaction_pointer_down", "xp_interaction_pointer_move", "xp_interaction_pointer_up", "xp_interaction_scroll_wheel", "xp_interaction_update", "xp_set_animation_playback_rate", "xp_update_animations");
            NativeRuntime.AddFunctions(rendering, "rendering", "xp_create_angle_surface", "xp_destroy_angle_surface", "xp_render_angle_surface", "xp_render", "xp_render_angle");
            NativeRuntime.AddFunctions(xamlCompletion, "xaml_completion", "xp_xaml_supported_attribute_count", "xp_xaml_supported_attribute_name", "xp_xaml_supported_element_count", "xp_xaml_supported_element_name");
            NativeRuntime.AddFunctions(logging, "logging", "xp_configure_logging", "xp_log_info");
        }

        private static NativeAbiTable ReadTable(IntPtr address, int functionCount) {
            var functionPointers = new IntPtr[functionCount];
            for (var index = 0; index < functionCount; ++index) {
                functionPointers[index] = Marshal.ReadIntPtr(address, sizeof(uint) * 2 + (int)IntPtr.Size * index);
            }
            return new NativeAbiTable { Version = (uint)Marshal.ReadInt32(address), Size = (uint)Marshal.ReadInt32(address, sizeof(uint)), FunctionPointers = functionPointers };
        }
        public static void ThrowIfFalse(bool result) {
            if (!result) {
                throw new InvalidOperationException(NativeRuntime.Metadata.GetLastError());
            }
        }

        public static class Abi {
            public static void EnsurePluginCompatibility() {
                var actualVersion = NativeRuntime.Methods.Metadata.xp_get_abi_version();
                if (actualVersion != NativeRuntime.PluginAbiVersion) {
                    throw new InvalidOperationException($"Preview-plugin ABI {actualVersion} несовместим с ABI {NativeRuntime.PluginAbiVersion} Previewer-а.");
                }
            }
        }

        public static class Metadata {
            public static string GetNavigationGraph(IntPtr session) {
                return NativeRuntime.ReadUtf8(value => NativeRuntime.Methods.Metadata.xp_get_navigation_graph(session, value, value.Length));
            }

            public static string GetPluginInfo() {
                return NativeRuntime.ReadUtf8(value => NativeRuntime.Methods.Metadata.xp_get_plugin_info(value, value.Length));
            }

            public static string GetInitialPageId(IntPtr session) {
                return NativeRuntime.ReadUtf8(value => NativeRuntime.Methods.Metadata.xp_get_initial_page_id(session, value, value.Length));
            }

            public static string GetLastError() {
                var value = NativeRuntime.Methods.Metadata.xp_last_error();
                return Marshal.PtrToStringUTF8(value) ?? "Unknown XamlRuntime error.";
            }
        }

        public static class Session {
            public static string GetSessionCurrentPage(IntPtr session) {
                return NativeRuntime.ReadUtf8(value => NativeRuntime.Methods.Session.xp_session_current_page(session, value, value.Length));
            }
        }

        public static class Element {
            public static string GetElementId(IntPtr element) {
                return Marshal.PtrToStringUTF8(NativeRuntime.Methods.Element.xp_element_id(element)) ?? string.Empty;
            }
        }

        public static class XamlCompletion {
            public static string GetSupportedAttributeName(string elementType, int index) {
                return Marshal.PtrToStringUTF8(NativeRuntime.Methods.XamlCompletion.xp_xaml_supported_attribute_name(elementType, index)) ?? string.Empty;
            }

            public static string GetSupportedElementName(int index) {
                return Marshal.PtrToStringUTF8(NativeRuntime.Methods.XamlCompletion.xp_xaml_supported_element_name(index)) ?? string.Empty;
            }
        }

        public static class Methods {
            public static class Metadata {
                public static uint xp_get_abi_version() {
                    return NativeRuntime.Get<Delegates.Metadata.xp_get_abi_version>("xp_get_abi_version")();
                }

                public static int xp_get_navigation_graph(IntPtr session, [Out] byte[] graphJson, int capacity) {
                    return NativeRuntime.Get<Delegates.Metadata.xp_get_navigation_graph>("xp_get_navigation_graph")(session, graphJson, capacity);
                }

                public static int xp_get_plugin_info([Out] byte[] pluginInfoJson, int capacity) {
                    return NativeRuntime.Get<Delegates.Metadata.xp_get_plugin_info>("xp_get_plugin_info")(pluginInfoJson, capacity);
                }

                public static int xp_get_initial_page_id(IntPtr session, [Out] byte[] pageId, int capacity) {
                    return NativeRuntime.Get<Delegates.Metadata.xp_get_initial_page_id>("xp_get_initial_page_id")(session, pageId, capacity);
                }

                public static int xp_navigate(IntPtr session, [MarshalAs(UnmanagedType.LPUTF8Str)] string transitionIds) {
                    return NativeRuntime.Get<Delegates.Metadata.xp_navigate>("xp_navigate")(session, transitionIds);
                }

                public static IntPtr xp_last_error() {
                    return NativeRuntime.Get<Delegates.Metadata.xp_last_error>("xp_last_error")();
                }
            }

            public static class Session {
                public static IntPtr xp_create_session(int width, int height) {
                    return NativeRuntime.Get<Delegates.Session.xp_create_session>("xp_create_session")(width, height);
                }

                public static void xp_destroy_session(IntPtr session) {
                    NativeRuntime.Get<Delegates.Session.xp_destroy_session>("xp_destroy_session")(session);
                }

                public static int xp_session_load_page(IntPtr session, [MarshalAs(UnmanagedType.LPUTF8Str)] string page) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_load_page>("xp_session_load_page")(session, page);
                }

                public static int xp_session_current_page(IntPtr session, [Out] byte[] page, int capacity) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_current_page>("xp_session_current_page")(session, page, capacity);
                }

                public static int xp_session_is_transitioning(IntPtr session) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_is_transitioning>("xp_session_is_transitioning")(session);
                }

                public static int xp_session_navigate_preview_route(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string target) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_navigate_preview_route>("xp_session_navigate_preview_route")(session, target);
                }

                public static int xp_session_navigate_preview_route_path(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string path) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_navigate_preview_route_path>("xp_session_navigate_preview_route_path")(session, path);
                }

                public static int xp_session_preview_route_graph(IntPtr session, [Out] StringBuilder graph, int capacity) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_preview_route_graph>("xp_session_preview_route_graph")(session, graph, capacity);
                }

                public static int xp_session_preview_page_title(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string page,
                    [Out] byte[] title,
                    int capacity) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_preview_page_title>("xp_session_preview_page_title")(session, page, title, capacity);
                }

                public static int xp_session_apply_preview_scenario(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string page,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string json) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_apply_preview_scenario>("xp_session_apply_preview_scenario")(session, page, json);
                }

                public static int xp_session_export_preview_state(IntPtr session) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_export_preview_state>("xp_session_export_preview_state")(session);
                }

                public static int xp_session_can_save_preview_state(IntPtr session) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_can_save_preview_state>("xp_session_can_save_preview_state")(session);
                }

                public static int xp_session_reload_markup(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string page,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string markup,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string sourcePath) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_reload_markup>("xp_session_reload_markup")(session, page, markup, sourcePath);
                }

                public static int xp_session_resize(IntPtr session, int width, int height) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_resize>("xp_session_resize")(session, width, height);
                }

                public static int xp_session_set_animation_playback_rate(IntPtr session, float value) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_set_animation_playback_rate>("xp_session_set_animation_playback_rate")(session, value);
                }

                public static int xp_session_pointer_down(IntPtr session, float x, float y) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_pointer_down>("xp_session_pointer_down")(session, x, y);
                }

                public static int xp_session_pointer_move(IntPtr session, float x, float y) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_pointer_move>("xp_session_pointer_move")(session, x, y);
                }

                public static int xp_session_pointer_up(IntPtr session, float x, float y) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_pointer_up>("xp_session_pointer_up")(session, x, y);
                }

                public static int xp_session_pointer_cancel(IntPtr session) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_pointer_cancel>("xp_session_pointer_cancel")(session);
                }

                public static int xp_session_cursor_kind(IntPtr session, float x, float y) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_cursor_kind>("xp_session_cursor_kind")(session, x, y);
                }

                public static int xp_session_inspect(IntPtr session, float x, float y, out NativeInspectionResult result) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_inspect>("xp_session_inspect")(session, x, y, out result);
                }

                public static int xp_session_set_inspection_wireframe(
                    IntPtr session,
                    float thickness,
                    int lineStyle,
                    NativeColor color,
                    NativeColor marginColor,
                    NativeColor paddingColor) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_set_inspection_wireframe>("xp_session_set_inspection_wireframe")(session, thickness, lineStyle, color, marginColor, paddingColor);
                }

                public static int xp_session_set_selected_wireframe(
                    IntPtr session,
                    float thickness,
                    int lineStyle,
                    NativeColor color,
                    NativeColor marginColor,
                    NativeColor paddingColor) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_set_selected_wireframe>("xp_session_set_selected_wireframe")(session, thickness, lineStyle, color, marginColor, paddingColor);
                }

                public static int xp_session_clear_inspection_wireframe(IntPtr session) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_clear_inspection_wireframe>("xp_session_clear_inspection_wireframe")(session);
                }

                public static int xp_session_clear_selected_inspection_element(IntPtr session) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_clear_selected_inspection_element>("xp_session_clear_selected_inspection_element")(session);
                }

                public static int xp_session_select_inspection_element(
                    IntPtr session,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string sourcePath,
                    int line,
                    int column) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_select_inspection_element>("xp_session_select_inspection_element")(session, sourcePath, line, column);
                }

                public static int xp_session_pin_inspection_element(IntPtr session) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_pin_inspection_element>("xp_session_pin_inspection_element")(session);
                }

                public static int xp_session_update(IntPtr session) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_update>("xp_session_update")(session);
                }

                public static int xp_session_render_angle_surface(IntPtr session, IntPtr surface, [Out] byte[] pixels, int stride, int capacity) {
                    return NativeRuntime.Get<Delegates.Session.xp_session_render_angle_surface>("xp_session_render_angle_surface")(session, surface, pixels, stride, capacity);
                }

            }

            public static class Element {
                public static IntPtr xp_create_element([MarshalAs(UnmanagedType.LPUTF8Str)] string type) {
                    return NativeRuntime.Get<Delegates.Element.xp_create_element>("xp_create_element")(type);
                }

                public static void xp_destroy_element(IntPtr element) {
                    NativeRuntime.Get<Delegates.Element.xp_destroy_element>("xp_destroy_element")(element);
                }

                public static int xp_items_remove_item(IntPtr target) {
                    return NativeRuntime.Get<Delegates.Element.xp_items_remove_item>("xp_items_remove_item")(target);
                }

                public static int xp_add_child(IntPtr parent, IntPtr child) {
                    return NativeRuntime.Get<Delegates.Element.xp_add_child>("xp_add_child")(parent, child);
                }

                public static int xp_set_attribute(
                    IntPtr element,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string name,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string value) {
                    return NativeRuntime.Get<Delegates.Element.xp_set_attribute>("xp_set_attribute")(element, name, value);
                }

                public static IntPtr xp_find_element(
                    IntPtr root,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string id) {
                    return NativeRuntime.Get<Delegates.Element.xp_find_element>("xp_find_element")(root, id);
                }

                public static int xp_layout(IntPtr root, float width, float height) {
                    return NativeRuntime.Get<Delegates.Element.xp_layout>("xp_layout")(root, width, height);
                }

                public static IntPtr xp_hit_test(IntPtr root, float x, float y) {
                    return NativeRuntime.Get<Delegates.Element.xp_hit_test>("xp_hit_test")(root, x, y);
                }

                public static IntPtr xp_hit_test_visual(IntPtr root, float x, float y) {
                    return NativeRuntime.Get<Delegates.Element.xp_hit_test_visual>("xp_hit_test_visual")(root, x, y);
                }

                public static int xp_hit_test_cursor_kind(IntPtr root, float x, float y) {
                    return NativeRuntime.Get<Delegates.Element.xp_hit_test_cursor_kind>("xp_hit_test_cursor_kind")(root, x, y);
                }

                public static int xp_element_bounds(IntPtr element, out NativeRect bounds) {
                    return NativeRuntime.Get<Delegates.Element.xp_element_bounds>("xp_element_bounds")(element, out bounds);
                }

                public static int xp_scroll_by(IntPtr root, float x, float y, float horizontalDelta, float verticalDelta) {
                    return NativeRuntime.Get<Delegates.Element.xp_scroll_by>("xp_scroll_by")(root, x, y, horizontalDelta, verticalDelta);
                }

                public static IntPtr xp_element_id(IntPtr element) {
                    return NativeRuntime.Get<Delegates.Element.xp_element_id>("xp_element_id")(element);
                }
            }

            public static class XamlCompletion {
                public static int xp_xaml_supported_attribute_count(
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string elementType) {
                    return NativeRuntime.Get<Delegates.XamlCompletion.xp_xaml_supported_attribute_count>("xp_xaml_supported_attribute_count")(elementType);
                }

                public static IntPtr xp_xaml_supported_attribute_name(
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string elementType,
                    int index) {
                    return NativeRuntime.Get<Delegates.XamlCompletion.xp_xaml_supported_attribute_name>("xp_xaml_supported_attribute_name")(elementType, index);
                }

                public static int xp_xaml_supported_element_count() {
                    return NativeRuntime.Get<Delegates.XamlCompletion.xp_xaml_supported_element_count>("xp_xaml_supported_element_count")();
                }

                public static IntPtr xp_xaml_supported_element_name(int index) {
                    return NativeRuntime.Get<Delegates.XamlCompletion.xp_xaml_supported_element_name>("xp_xaml_supported_element_name")(index);
                }
            }

            public static class Interaction {
                public static IntPtr xp_create_session(int width, int height) {
                    return NativeRuntime.Methods.Session.xp_create_session(width, height);
                }

                public static void xp_destroy_session(IntPtr session) {
                    NativeRuntime.Methods.Session.xp_destroy_session(session);
                }

                public static int xp_add_storyboard_animation(IntPtr element, int trigger,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string? name,
                    [In] IntPtr[] keys, [In] IntPtr[] values, int count) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_add_storyboard_animation>("xp_add_storyboard_animation")(element, trigger, name, keys, values, count);
                }

                public static int xp_attach_animations(IntPtr root, IntPtr animations) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_attach_animations>("xp_attach_animations")(root, animations);
                }

                public static int xp_set_page_transition(
                    IntPtr root,
                    IntPtr animations,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string from,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string to,
                    int backward,
                    int visible) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_set_page_transition>("xp_set_page_transition")(root, animations, from, to, backward, visible);
                }

                public static int xp_add_storyboard_track(
                    IntPtr element,
                    int trigger,
                    int property,
                    float from,
                    float to,
                    int durationMilliseconds,
                    int easing) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_add_storyboard_track>("xp_add_storyboard_track")(element, trigger, property, from, to, durationMilliseconds, easing);
                }

                public static int xp_add_visual_state_track(
                    IntPtr scope,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string groupName,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string stateName,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string targetName,
                    int property, float from, float to, int durationMilliseconds, int easing) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_add_visual_state_track>("xp_add_visual_state_track")(scope, groupName, stateName, targetName, property, from, to, durationMilliseconds, easing);
                }

                public static int xp_go_to_visual_state(
                    IntPtr scope,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string groupName,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string stateName,
                    int useTransitions) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_go_to_visual_state>("xp_go_to_visual_state")(scope, groupName, stateName, useTransitions);
                }

                public static int xp_scroll_begin(IntPtr root, IntPtr animations, float x, float y) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_scroll_begin>("xp_scroll_begin")(root, animations, x, y);
                }

                public static int xp_scroll_drag(IntPtr animations, float verticalDelta) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_scroll_drag>("xp_scroll_drag")(animations, verticalDelta);
                }

                public static void xp_scroll_end(IntPtr animations) {
                    NativeRuntime.Get<Delegates.Interaction.xp_scroll_end>("xp_scroll_end")(animations);
                }

                public static int xp_set_render_offset_x(IntPtr element, float value) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_set_render_offset_x>("xp_set_render_offset_x")(element, value);
                }

                public static int xp_animate_render_offset_x(
                    IntPtr element,
                    IntPtr animations,
                    float value,
                    int durationMilliseconds) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_animate_render_offset_x>("xp_animate_render_offset_x")(element, animations, value, durationMilliseconds);
                }

                public static int xp_handle_tap(IntPtr element, IntPtr animations) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_handle_tap>("xp_handle_tap")(element, animations);
                }

                public static int xp_handle_pointer_down(IntPtr element, IntPtr animations) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_handle_pointer_down>("xp_handle_pointer_down")(element, animations);
                }

                public static int xp_handle_pointer_up(IntPtr element, IntPtr animations) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_handle_pointer_up>("xp_handle_pointer_up")(element, animations);
                }

                public static IntPtr xp_create_animation_controller() {
                    return NativeRuntime.Get<Delegates.Interaction.xp_create_animation_controller>("xp_create_animation_controller")();
                }

                public static void xp_destroy_animation_controller(IntPtr animations) {
                    NativeRuntime.Get<Delegates.Interaction.xp_destroy_animation_controller>("xp_destroy_animation_controller")(animations);
                }

                public static IntPtr xp_create_interaction_controller() {
                    return NativeRuntime.Get<Delegates.Interaction.xp_create_interaction_controller>("xp_create_interaction_controller")();
                }

                public static void xp_destroy_interaction_controller(IntPtr controller) {
                    NativeRuntime.Get<Delegates.Interaction.xp_destroy_interaction_controller>("xp_destroy_interaction_controller")(controller);
                }

                public static int xp_interaction_pointer_down(
                    IntPtr controller, IntPtr root, IntPtr animations, float x, float y) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_interaction_pointer_down>("xp_interaction_pointer_down")(controller, root, animations, x, y);
                }

                public static int xp_interaction_pointer_move(IntPtr controller, float x, float y) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_interaction_pointer_move>("xp_interaction_pointer_move")(controller, x, y);
                }

                public static int xp_interaction_pointer_up(
                    IntPtr controller, IntPtr root, IntPtr animations, float x, float y, out NativeInteractionResult result) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_interaction_pointer_up>("xp_interaction_pointer_up")(controller, root, animations, x, y, out result);
                }

                public static int xp_interaction_scroll_wheel(
                    IntPtr controller, IntPtr root, float x, float y, float horizontalDelta, float verticalDelta) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_interaction_scroll_wheel>("xp_interaction_scroll_wheel")(controller, root, x, y, horizontalDelta, verticalDelta);
                }

                public static int xp_interaction_update(IntPtr controller) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_interaction_update>("xp_interaction_update")(controller);
                }

                public static int xp_set_animation_playback_rate(IntPtr animations, float playbackRate) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_set_animation_playback_rate>("xp_set_animation_playback_rate")(animations, playbackRate);
                }

                public static int xp_update_animations(IntPtr animations) {
                    return NativeRuntime.Get<Delegates.Interaction.xp_update_animations>("xp_update_animations")(animations);
                }
            }

            public static class Rendering {
                public static IntPtr xp_create_angle_surface(
                    int width,
                    int height,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string fontPath,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string resourceRoot) {
                    return NativeRuntime.Get<Delegates.Rendering.xp_create_angle_surface>("xp_create_angle_surface")(width, height, fontPath, resourceRoot);
                }

                public static void xp_destroy_angle_surface(IntPtr surface) {
                    NativeRuntime.Get<Delegates.Rendering.xp_destroy_angle_surface>("xp_destroy_angle_surface")(surface);
                }

                public static int xp_render_angle_surface(
                    IntPtr surface,
                    IntPtr root,
                    [Out] byte[] pixels,
                    int stride,
                    int capacity) {
                    return NativeRuntime.Get<Delegates.Rendering.xp_render_angle_surface>("xp_render_angle_surface")(surface, root, pixels, stride, capacity);
                }

                public static int xp_render(IntPtr root, [Out] NativeCommand[]? commands, int capacity) {
                    return NativeRuntime.Get<Delegates.Rendering.xp_render>("xp_render")(root, commands, capacity);
                }

                public static int xp_render_angle(
                    IntPtr root,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string fontPath,
                    int width,
                    int height,
                    [MarshalAs(UnmanagedType.LPUTF8Str)] string resourceRoot,
                    [Out] byte[] pixels,
                    int stride,
                    int capacity) {
                    return NativeRuntime.Get<Delegates.Rendering.xp_render_angle>("xp_render_angle")(root, fontPath, width, height, resourceRoot, pixels, stride, capacity);
                }
            }

            public static class Logging {
                public static void xp_configure_logging([MarshalAs(UnmanagedType.LPUTF8Str)] string filePath) {
                    NativeRuntime.Get<Delegates.Logging.xp_configure_logging>("xp_configure_logging")(filePath);
                }

                public static void xp_log_info([MarshalAs(UnmanagedType.LPUTF8Str)] string message) {
                    NativeRuntime.Get<Delegates.Logging.xp_log_info>("xp_log_info")(message);
                }
            }
        }

        private static string ReadUtf8(Func<byte[], int> operation) {
            var value = new byte[16384];
            ThrowIfFalse(operation(value) != 0);
            var length = Array.IndexOf(value, (byte)0);
            return Encoding.UTF8.GetString(value, 0, length < 0 ? value.Length : length);
        }
    }
}