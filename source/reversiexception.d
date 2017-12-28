
class ReversiException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) pure @safe {
        super(msg, file, line);
    }
}
