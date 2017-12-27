enum Mark : int {
	BLACK = 1,
	WHITE = -1,
	EMPTY = 0,
	INVALID = 999,
}

struct NextAction {
private:
	int type;
	Position p;

	@disable this();
	this(int type) pure nothrow @safe {
		this.type = type;
	}
public:
	static NextAction PutAt(Position p) pure nothrow @safe {
		auto a = NextAction(0);
		a.p = p;
		return a;
	}
	static NextAction Pass() pure nothrow @safe {
		auto a = NextAction(1);
		return a;
	}
	bool IsPass() pure const nothrow @safe {
		return this.type == 1;
	}
	Position GetPutAt() pure const @safe{
		if (this.type != 0) {
			throw new Exception("This action is not put, so couldn't get position where to put");
		}
		return this.p;
	}
}


struct Position {
public:
	int x;
	int y;
}

interface ReversiPlayer {
public:
	void SetMark(Mark) pure nothrow @safe;
	Mark GetMark() pure nothrow const @safe;
	NextAction GetNextAction(const ReversiBoard) pure const;
}

class ReversiUser : ReversiPlayer {
private:
	Mark mark;
	NextAction nextAction;
public:
	this(Mark mark) pure nothrow @safe {
		this.mark = mark;
		this.nextAction = NextAction.Pass();
	}
	void SetMark(Mark mark) pure nothrow @safe {
		this.mark = mark;
	}
	Mark GetMark() pure const nothrow @safe {
		return this.mark;
	}
	void SetNextAction(NextAction nextAction) {
		this.nextAction = nextAction;
	}
	NextAction GetNextAction(const ReversiBoard board) pure const {
		return nextAction;
	}

}

class ReversiBoard {
private:
	Mark[][] board;
public:
	const int size = 8;
	this() pure nothrow @safe {
		this.board = new Mark[][](size,size);
		for (int y = 0; y < size; y++) {
			for (int x = 0; x < size; x++) {
				this.board[y][x] = Mark.EMPTY;
			}
		}
		this.board[3][3] = Mark.WHITE;
		this.board[3][4] = Mark.BLACK;
		this.board[4][3] = Mark.BLACK;
		this.board[4][4] = Mark.WHITE;
	}
	this(const(Mark[][]) board) pure nothrow @safe {
		import std.conv : to;
		this.board = board.to!(Mark[][]); // copy 
	}
	this(int[] board) pure nothrow @safe {
		this.board = new Mark[][](size,size);
		for (int y = 0; y < size; y++) {
			for (int x = 0; x < size; x++) {
				this.board[y][x] = cast(Mark)board[y*8+x];
			}
		}
	}

	/// return specific position status of board
	Mark At(int x, int y) pure nothrow const @safe {
		if (0 <= x && x < this.size && 0 <= y && y < this.size) {
			return board[y][x];
		}
		return Mark.INVALID;
	}

	int[] IntArray() pure nothrow const @safe {
		int[] xs = [];
		for (int y = 0; y < this.size; y++) {
			for (int x = 0; x < this.size; x++) {
				xs ~= this.At(x,y);
			}
		}
		return xs;
	}

	/// return string expression of board status
	string String() pure nothrow const @safe {
		import std.range : repeat;
		import std.array : join;
		import std.conv : to;

		char[] buf = [];
		buf ~= "v01234567v\n";
		for (int y = 0; y < this.size; y++) {
			buf ~= "|";
			for (int x = 0; x < this.size; x++) {
				if (this.At(x,y) == Mark.BLACK) {
					buf ~= "*";
				}
				else if (this.At(x,y) == Mark.WHITE) {
					buf ~= "o";
				}
				else {
					buf ~= "-";
				}
			}
			buf ~= y.to!string~"\n";
		}
		buf ~= "^".repeat(10).join("") ~ "\n";

		return buf.to!string;
	}

	Position[] ReversesWhenPut(int x, int y, Mark mark) pure const @safe {
		with (Mark) {
			if (this.At(x,y) != EMPTY) {
				return [];
			}
			Position[] poses = [];

			auto dx = [-1, 0, 1, -1, 1, -1, 0, 1];
			auto dy = [-1, -1, -1, 0, 0, 1, 1, 1];
			
			// search 8-neighbor
			for (int i = 0; i < dx.length; i++) {
				if (this.At(x+dx[i], y+dy[i]) == -mark) {
					Position[] candidates = [];
					bool flag = false;
					int j = 1;
					// go next next next ... until a == mark
					while (true) {
						auto a = this.At(x+dx[i]*j, y+dy[i]*j);
						if (a == -mark) {
							candidates ~= Position(x+dx[i]*j, y+dy[i]*j);
						}
						else if (a == mark) {
							flag = true;
							break;
						}
						else {
							break;
						}
						j++;
					}
					// add revesed positions
					if (flag && candidates.length > 0) {
						poses ~= candidates;
					}
				}
			}
			return poses;
		}
	}

	ReversiBoard PutAt(int x, int y, Mark mark) pure const @safe {
		import std.format : format;
		auto revs = ReversesWhenPut(x, y, mark);
		if (revs.length == 0) {
			throw new Exception("Position(%d, %d) is not puttable for %s".format(x,y, mark));
		}
		ReversiBoard copy = new ReversiBoard(this.board);
		copy.board[y][x] = mark;
		foreach (p; revs) {
			copy.board[p.y][p.x] = mark;
		}
		return copy;
	}

	Position[] ListupPuttables(Mark mark) pure const @safe {
		Position[] puttables = [];
		for (int x = 0; x < this.size; x++) {
			for (int y = 0; y < this.size; y++) {
				if (IsPuttableAt(x,y,mark)) {
					puttables ~= Position(x,y);
				}
			}
		}
		return puttables;
	}
	
	bool IsPuttableAt(int x, int y, Mark mark) pure const @safe {
		with (Mark) {
			if (this.At(x,y) != EMPTY) {
				return false;
			}

			auto dx = [-1, 0, 1, -1, 1, -1, 0, 1];
			auto dy = [-1, -1, -1, 0, 0, 1, 1, 1];
			
			// search 8-neighbor
			for (int i = 0; i < dx.length; i++) {
				if (this.At(x+dx[i], y+dy[i]) == -mark) {
					bool flag = true;
					int j = 2;
					// go next next next ... until a == mark
					while (true) {
						auto a = this.At(x+dx[i]*j, y+dy[i]*j);
						if (a == -mark) {
						}
						else if (a == mark) {
							break;
						}
						else {
							flag = false;
							break;
						}
						j++;
					}
					if (flag) {
						return true;
					}
				}
			}
			return false;
		}
	}

	uint Count(Mark mark) pure nothrow const @safe {
		uint cnt = 0;
		for (int x = 0; x < this.size; x++) {
			for (int y = 0; y < this.size; y++) {
				if (this.At(x,y) == mark) {
					cnt++;
				}
			}
		}
		return cnt;
	}

	bool IsGameEnd() pure const @safe{
		if (ListupPuttables(Mark.BLACK).length == 0 && ListupPuttables(Mark.WHITE).length == 0)  {
			return true;
		}
		for (int y = 0; y < this.size; y++) {
			for (int x = 0; x < this.size; x++) {
				if (this.At(x,y) == Mark.EMPTY) {
					return false;
				}
			}
		}
		return true;
	}
}

class ReversiManager {
private:
	ReversiBoard board;
	ReversiPlayer[] players;
	int turn;
	int turnPlayerIndex;

public:
	this(ReversiPlayer player1, ReversiPlayer player2) pure @safe {
		this.board = new ReversiBoard();
		if (player1 is null) {
			throw new Exception("Player1 is null");
		}
		if (player2 is null) {
			throw new Exception("Player2 is null");
		}
		this.players = [player1, player2];
		this.turn = 0;
		this.turnPlayerIndex = 0;
	}
	int GetTurn() pure const nothrow @safe{
		return this.turn;
	}
	void GoNextTurn() pure @safe {
		this.turn ++;
		this.turnPlayerIndex = (this.turnPlayerIndex+1)%2;
	}
	NextAction Next() pure {
		auto nextAction = GetTurnPlayer().GetNextAction(this.board);
		if (! nextAction.IsPass()) {
			auto putAt = nextAction.GetPutAt();
			this.board = board.PutAt(putAt.x, putAt.y, GetTurnPlayer().GetMark());
		}
		if (! this.board.IsGameEnd()) {
			GoNextTurn();
		}
		return nextAction;
	}
	ReversiBoard GetBoard() pure nothrow @safe {
		return this.board;
	}
	ReversiPlayer GetTurnPlayer() pure @safe {
		return players[turnPlayerIndex];
	}
}
