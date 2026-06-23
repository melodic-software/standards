namespace Sample.Library;

/// <summary>Computes running totals over a sequence of amounts.</summary>
public sealed class Calculator
{
    private readonly List<int> _amounts = [];

    /// <summary>Adds an amount to the running set.</summary>
    public void Add(int amount) => _amounts.Add(amount);

    /// <summary>Returns the sum of all amounts.</summary>
    public int Total() => _amounts.Sum();

    /// <summary>Describes a total relative to zero.</summary>
    public static string Describe(int total) => total switch
    {
        < 0 => "negative",
        0 => "zero",
        _ => "positive",
    };
}
