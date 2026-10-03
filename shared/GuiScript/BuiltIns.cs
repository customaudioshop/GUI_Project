namespace GuiScript;

/// <summary>Device protocol ids used in the package's device list.</summary>
public static class Protocols
{
    public const string Tcp = "tcp";
    public const string Udp = "udp";
    public const string Serial = "serial";
    public const string ArtNet = "artnet";
    public const string Sacn = "sacn";
    public const string DmxUsb = "dmx-usb";
    public const string Midi = "midi";
    public const string Gpio = "gpio";
    public const string Ir = "ir";
}

public static class BuiltIns
{
    public static CommandRegistry CreateCommands()
    {
        string[] stream = { Protocols.Tcp, Protocols.Udp, Protocols.Serial };
        string[] dmx = { Protocols.ArtNet, Protocols.Sacn, Protocols.DmxUsb };

        var r = new CommandRegistry();
        r.Register("send", "Send text to a TCP/UDP/serial device",
            ParamSpec.Device("device", stream), ParamSpec.Text("data"));
        r.Register("sendhex", "Send raw bytes written as hex, e.g. \"01 A0 FF\"",
            ParamSpec.Device("device", stream), ParamSpec.Hex("bytes"));

        r.Register("dmx", "Set one DMX channel",
            ParamSpec.Device("device", dmx), ParamSpec.Int("channel", 1, 512), ParamSpec.Int("value", 0, 255));
        r.Register("dmx.fade", "Fade one DMX channel to a value over time",
            ParamSpec.Device("device", dmx), ParamSpec.Int("channel", 1, 512), ParamSpec.Int("value", 0, 255),
            ParamSpec.Int("ms", 0, 60_000));

        r.Register("midi.note", "Send a MIDI note-on (velocity 0 = note-off)",
            ParamSpec.Device("device", Protocols.Midi), ParamSpec.Int("channel", 1, 16),
            ParamSpec.Int("note", 0, 127), ParamSpec.Int("velocity", 0, 127));
        r.Register("midi.cc", "Send a MIDI control change",
            ParamSpec.Device("device", Protocols.Midi), ParamSpec.Int("channel", 1, 16),
            ParamSpec.Int("controller", 0, 127), ParamSpec.Int("value", 0, 127));
        r.Register("midi.pc", "Send a MIDI program change",
            ParamSpec.Device("device", Protocols.Midi), ParamSpec.Int("channel", 1, 16),
            ParamSpec.Int("program", 0, 127));

        r.Register("gpio", "Set a GPIO output pin",
            ParamSpec.Device("device", Protocols.Gpio), ParamSpec.Int("pin", 0, 63), ParamSpec.Choice("state", "on", "off"));
        r.Register("ir", "Blast a learned IR code",
            ParamSpec.Device("device", Protocols.Ir), ParamSpec.Text("code"));

        r.Register("wait", "Pause the script (milliseconds)", ParamSpec.Int("ms", 0, 60_000));
        r.Register("page", "Switch to another page", ParamSpec.Page("name"));
        r.Register("log", "Write a message to the player log", ParamSpec.AnyValue("message"));
        return r;
    }

    public static FunctionRegistry CreateFunctions()
    {
        const ScriptType N = ScriptType.Number;
        var r = new FunctionRegistry();
        r.Register("clamp", N, "Limit a value to a range: clamp(value, min, max)", N, N, N);
        r.Register("min", N, "Smaller of two numbers", N, N);
        r.Register("max", N, "Larger of two numbers", N, N);
        r.Register("round", N, "Round to the nearest whole number", N);
        r.Register("floor", N, "Round down", N);
        r.Register("ceil", N, "Round up", N);
        r.Register("abs", N, "Absolute value", N);
        r.Register("scale", N, "Map a value between ranges: scale(value, inMin, inMax, outMin, outMax)", N, N, N, N, N);
        r.Register("str", ScriptType.String, "Convert to text", ScriptType.Any);
        r.Register("num", N, "Convert text to a number", ScriptType.String);
        return r;
    }
}

public static class HexBytes
{
    /// <summary>Parses "01 A0 FF" or "01A0FF". Spaces are optional; each byte needs two digits.</summary>
    public static bool TryParse(string text, out byte[] bytes)
    {
        bytes = Array.Empty<byte>();
        string digits = string.Concat(text.Where(c => c != ' '));
        if (digits.Length == 0 || digits.Length % 2 != 0 || !digits.All(char.IsAsciiHexDigit)) return false;
        bytes = Convert.FromHexString(digits);
        return true;
    }
}
