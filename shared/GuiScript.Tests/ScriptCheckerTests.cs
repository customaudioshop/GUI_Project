using GuiScript;

namespace GuiScript.Tests;

public class ScriptCheckerTests
{
    private static ValidationContext Context() => new()
    {
        Devices =
        {
            ["mixer1"] = Protocols.Tcp,
            ["light1"] = Protocols.ArtNet,
            ["synth"] = Protocols.Midi,
            ["relay"] = Protocols.Gpio,
            ["tv"] = Protocols.Ir,
        },
        Pages = { "main", "scene2" },
        ContextVariables = { ["value"] = ScriptType.Number },
    };

    private static CheckResult Check(string source) => ScriptChecker.Check(source, Context());

    private static void AssertValid(string source)
    {
        var result = Check(source);
        Assert.True(result.IsValid, string.Join("\n", result.Diagnostics));
    }

    private static Diagnostic AssertSingle(string source, string code)
    {
        var result = Check(source);
        var diagnostic = Assert.Single(result.Diagnostics);
        Assert.Equal(code, diagnostic.Code);
        return diagnostic;
    }

    [Fact]
    public void FullExampleIsValid() => AssertValid("""
        # Fader moved: set mixer volume and light level
        set $level = round(scale($value, 0, 1, 0, 255))
        send mixer1 "SET CH1 VOL $level\n"
        dmx light1 1 ($level)
        sendhex mixer1 "01 A0 FF"

        if $value > 0.5
            gpio relay 3 on
        elif $value > 0.2
            midi.cc synth 1 7 (round($value * 127))
        else
            gpio relay 3 off
        end

        repeat 3
            ir tv "power"
            wait 200
        end
        page "scene2"
        """);

    [Fact]
    public void EmptyScriptIsValid() => AssertValid("");

    [Fact]
    public void UnknownCommandSuggestsClosest()
    {
        var d = AssertSingle("sned mixer1 \"hi\"", Codes.UnknownCommand);
        Assert.Contains("'send'", d.Message);
        Assert.Equal(new SourceSpan(1, 1, 4), d.Span);
    }

    [Fact]
    public void WrongArgumentCountShowsUsage()
    {
        var d = AssertSingle("dmx light1 1", Codes.ArgumentCount);
        Assert.Contains("dmx <device> <channel> <value>", d.Message);
    }

    [Theory]
    [InlineData("dmx light1 0 255")]
    [InlineData("dmx light1 513 255")]
    [InlineData("dmx light1 1 256")]
    [InlineData("dmx light1 1 (200 + 100)")]
    [InlineData("midi.note synth 17 60 100")]
    public void ConstantOutOfRange(string source) => AssertSingle(source, Codes.OutOfRange);

    [Fact]
    public void NonIntegerChannel() => AssertSingle("dmx light1 1.5 255", Codes.NotInteger);

    [Fact]
    public void UnknownDeviceSuggestsClosest()
    {
        var d = AssertSingle("send mixr1 \"hi\"", Codes.UnknownDevice);
        Assert.Contains("'mixer1'", d.Message);
    }

    [Fact]
    public void DeviceWithWrongProtocol()
    {
        var d = AssertSingle("dmx mixer1 1 255", Codes.DeviceProtocolMismatch);
        Assert.Contains("tcp", d.Message);
    }

    [Fact]
    public void DeviceMustBeName() => AssertSingle("send \"mixer1\" \"hi\"", Codes.TypeMismatch);

    [Fact]
    public void UndefinedVariableReportedOnce()
    {
        var d = AssertSingle("send mixer1 \"$levl\"\nsend mixer1 \"$levl\"", Codes.UndefinedVariable);
        Assert.Equal(1, d.Span.Line);
    }

    [Fact]
    public void UndefinedVariableSuggestsClosest()
    {
        var d = AssertSingle("set $level = 1\ndmx light1 1 ($levl)", Codes.UndefinedVariable);
        Assert.Contains("'$level'", d.Message);
    }

    [Fact]
    public void ContextVariableIsReadOnly() => AssertSingle("set $value = 1", Codes.ReadOnlyVariable);

    [Fact]
    public void VariableCannotChangeType() =>
        AssertSingle("set $a = 1\nset $a = \"x\"", Codes.VariableTypeChanged);

    [Fact]
    public void TypeMismatchInArithmetic() => AssertSingle("set $a = \"x\" * 2", Codes.TypeMismatch);

    [Fact]
    public void StringConcatenationIsAllowed() => AssertValid("set $a = \"CH\" + 1\nsend mixer1 $a");

    [Fact]
    public void ConditionMustBeBool() => AssertSingle("if $value\nend", Codes.TypeMismatch);

    [Fact]
    public void ConstantConditionWarns()
    {
        var result = Check("if 1 > 2\nend");
        Assert.True(result.IsValid);
        Assert.Equal(Codes.ConstantCondition, Assert.Single(result.Diagnostics).Code);
    }

    [Fact]
    public void InvalidHex() => AssertSingle("sendhex mixer1 \"01 G0\"", Codes.InvalidHex);

    [Fact]
    public void InvalidChoice()
    {
        var d = AssertSingle("gpio relay 3 high", Codes.InvalidChoice);
        Assert.Contains("on, off", d.Message);
    }

    [Fact]
    public void QuotedChoiceIsAllowed() => AssertValid("gpio relay 3 \"on\"");

    [Fact]
    public void UnknownPage() => AssertSingle("page \"scene3\"", Codes.UnknownPage);

    [Fact]
    public void BarePageNameAsksForQuotes() => AssertSingle("page main", Codes.TypeMismatch);

    [Fact]
    public void BareNameIsNotAValue() => AssertSingle("send mixer1 hello", Codes.NotAValue);

    [Fact]
    public void UnknownFunction() => AssertSingle("set $a = clmp(1, 0, 2)", Codes.UnknownFunction);

    [Fact]
    public void FunctionArgumentCount() => AssertSingle("set $a = clamp(1, 2)", Codes.ArgumentCount);

    [Fact]
    public void DivisionByConstantZero() => AssertSingle("set $a = $value / 0", Codes.DivisionByZero);

    [Fact]
    public void RepeatCountMustBeConstant() => AssertSingle("repeat $value\nend", Codes.RepeatNotConstant);

    [Theory]
    [InlineData("repeat 0\nend")]
    [InlineData("repeat 1001\nend")]
    [InlineData("repeat 2.5\nend")]
    public void RepeatCountOutOfRange(string source) => AssertSingle(source, Codes.RepeatOutOfRange);

    [Fact]
    public void NestingLimit()
    {
        string source = string.Concat(Enumerable.Repeat("repeat 2\n", 9)) + string.Concat(Enumerable.Repeat("end\n", 9));
        AssertSingle(source, Codes.NestingTooDeep);
    }

    [Fact]
    public void LineLimit()
    {
        string source = string.Join("\n", Enumerable.Repeat("wait 1", 501));
        AssertSingle(source, Codes.TooManyLines);
    }

    [Fact]
    public void MissingEndPointsAtOpener()
    {
        var d = AssertSingle("wait 1\nif $value > 0\n  wait 1", Codes.MissingEnd);
        Assert.Equal(2, d.Span.Line);
    }

    [Fact]
    public void StrayEnd() => AssertSingle("wait 1\nend", Codes.StrayBlockKeyword);

    [Fact]
    public void UnparenthesizedCalculationGivesHint()
    {
        var d = AssertSingle("dmx light1 1 $value * 2", Codes.UnexpectedToken);
        Assert.Contains("parentheses", d.Message);
    }

    [Fact]
    public void AssignmentWithoutSetGivesHint()
    {
        var d = AssertSingle("$a = 1", Codes.UnexpectedToken);
        Assert.Contains("set $a", d.Message);
    }

    [Fact]
    public void NegativeNumberArgument() => AssertSingle("dmx light1 -1 0", Codes.OutOfRange);

    [Fact]
    public void UnterminatedString() => AssertSingle("send mixer1 \"hi", Codes.UnterminatedString);

    [Fact]
    public void InvalidEscape() => AssertSingle("send mixer1 \"a\\qb\"", Codes.InvalidEscape);

    [Fact]
    public void DollarWithoutName() => AssertSingle("send mixer1 \"cost $5\"", Codes.BadVariableName);

    [Fact]
    public void EscapedDollarIsText() => AssertValid("send mixer1 \"cost \\$5\"");

    [Fact]
    public void InvalidNumber() => AssertSingle("wait 12abc", Codes.InvalidNumber);

    [Fact]
    public void HexNumberLiteral() => AssertValid("dmx light1 0x10 0xFF");

    [Fact]
    public void UnexpectedCharacter() => AssertSingle("wait 1 ;", Codes.UnexpectedChar);

    [Fact]
    public void ErrorsOnSeveralLinesAreAllReportedInOrder()
    {
        var result = Check("sned mixer1 \"a\"\ndmx light1 999 0\nsend mixr1 \"b\"");
        Assert.Equal(new[] { 1, 2, 3 }, result.Diagnostics.Select(d => d.Span.Line));
    }

    [Fact]
    public void BrokenIfConditionStillChecksBody()
    {
        var result = Check("if $value >\n  dmx light1 999 0\nend");
        Assert.Equal(new[] { Codes.ExpectedExpression, Codes.OutOfRange }, result.Diagnostics.Select(d => d.Code));
    }

    [Fact]
    public void CustomCommandsAreChecked()
    {
        var context = Context();
        context.Commands.Register("mixer.mute", "Mute a mixer channel",
            ParamSpec.Device("device", Protocols.Tcp), ParamSpec.Int("channel", 1, 32), ParamSpec.Bool("muted"));

        Assert.True(ScriptChecker.Check("mixer.mute mixer1 4 true", context).IsValid);
        var result = ScriptChecker.Check("mixer.mute mixer1 40 true", context);
        Assert.Equal(Codes.OutOfRange, Assert.Single(result.Diagnostics).Code);
    }
}
