import std.socket;
import std.stdio;
import std.json;
import std.random;
import std.conv;
import util;
import reversi;

class ReversiException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

/// Reversi Battle
class Battle {
public:
	static ulong nextId = 0;  /// unique battle id
	ReversiManager reversi;
	ulong id;
	User[] us;
	ReversiUser[] ps;
	this(User a, User b) {
		this.id = nextId;
		nextId++;
		if (dice(1,1) == 0) {
			this.us = [a, b];
		} else {
			this.us = [b, a];
		}
		this.ps = [new ReversiUser(Mark.BLACK), new ReversiUser(Mark.WHITE)];
		this.reversi = new ReversiManager(ps[0], ps[1]);

		start();
	}

	/**
     * Battle start script
     */
	void start() {
		{
			JSONValue json;
			json["result"] = "true";
			json["first"] = "true";
			json["mark"] = "black";
			us[0].connection.socket.emitln(json);
		}

		{
			JSONValue json;
			json["result"] = "true";
			json["first"] = "false";
			json["mark"] = "white";
			us[1].connection.socket.emitln(json);
		}
	}

	void atGameEnd(ulong winner) {
		auto loser = (winner + 1) % 2;
		if (us[winner].rating > us[loser].rating) {
			us[winner].rating += 1;
		}
		else if (us[winner].rating == us[loser].rating) {
			us[winner].rating += 2;
		}
		else {
			us[winner].rating += 3;
			if (us[loser].rating > 0) {
				us[loser].rating -= 1;
			}
		}
	}

	/**
     * turn action
     */
	void doAct(User user, JSONValue action) {
		try {
			auto turnP = this.ps[reversi.GetTurn()%2];
			auto nextP = this.ps[(reversi.GetTurn()+1)%2];
			auto nextUser = this.us[(reversi.GetTurn()+1)%2];
			if (us[reversi.GetTurn()%2] !is user) { throw new Exception("not your turn"); }
			if (action["action"].str() == "put") {
				auto x = action["pos"].array()[0].integer();
				auto y = action["pos"].array()[1].integer();
				turnP.SetNextAction(NextAction.PutAt(Position(cast(int)x,cast(int)y)));
				reversi.Next();

				bool isGameEnd = false;
				bool turnWin = false;
				bool isDraw = false;
				if (reversi.GetBoard().IsGameEnd()) {
					isGameEnd = true;
					auto turnCount = reversi.GetBoard().Count(turnP.GetMark());
					auto nextCount = reversi.GetBoard().Count(nextP.GetMark());
					if (turnCount == nextCount) {
						isDraw = true;
					}
					else if (turnCount > nextCount) {
						turnWin = true;
						atGameEnd(reversi.GetTurn()%2);
					}
					else {
						atGameEnd((reversi.GetTurn()+1)%2);
					}
				}
				
				{
					JSONValue json;
					json["result"] = "true";
					json["isGameEnd"] = isGameEnd.to!string;
					if (isGameEnd) {
						json["isDraw"] = isDraw.to!string;
						json["youWin"] = turnWin.to!string;
					}
					user.connection.socket.emitln(json);
				}

				{
					JSONValue json;
					json["result"] = "true";
					json["action"] = "put";
					json["pos"] = JSONValue([x,y]);
					json["isGameEnd"] = isGameEnd.to!string;
					if (isGameEnd) {
						json["isDraw"] = isDraw.to!string;
						json["youWin"] = (!turnWin).to!string;
					}
					nextUser.connection.socket.emitln(json);
				}

			}
			else if (action["action"].str() == "pass" && reversi.GetBoard.ListupPuttables(turnP.GetMark()).length == 0) {
				turnP.SetNextAction(NextAction.Pass());
				reversi.Next();

				{
					JSONValue json;
					json["result"] = "true";
					json["isGameEnd"] = "false";
					user.connection.socket.emitln(json);
				}

				{
					JSONValue json;
					json["result"] = "true";
					json["action"] = "pass";
					json["isGameEnd"] = "false";
					nextUser.connection.socket.emitln(json);
				}
			}
			else {
				throw new Exception("invalid action" ~ action.to!string);
			}
		}
		catch (Exception e) {
			writeln(e);
			JSONValue json;
			json["result"] = "false";
			json["msg"] = e.msg;
			user.connection.socket.emitln(json);
		}
	}

	void dead(User a) {
		JSONValue json;
		json["result"] = "true";
		json["action"] = "closed";
		json["isGameEnd"] = "true";
		json["isDraw"] = "false";
		json["youWin"] = "true";
		if (us[0] is a) {
			atGameEnd(1);
			if (us[1].connection.socket.isAlive) {
				us[1].connection.socket.emitln(json);
			}
		}
		else {
			atGameEnd(0);
			if (us[0].connection.socket.isAlive) {
				us[0].connection.socket.emitln(json);
			}
		}
		us[0].connection.close();
		us[1].connection.close();
	}
}

/// User
class User {
private:
	this() {}   /// constructor
public:
	static User[string] users;    /// all user list
	static int[string] actives;   /// active user list
	static int[string] waitings;  /// usernames who waiting for battle 

	string username;   /// username[unique]
	string password;   /// password
	ulong rating;      /// rating
	Connection connection;  /// connection

	/**
	 * Register new user with username and password
     * Throws: ReversiException on username is not unique or username or password is empty
     */
	static void register(string username, string password) {
		if (username.length == 0 || password.length == 0) {
			throw new ReversiException("(username > 0) && (password > 0)");
		}
		if (username in users) {
			throw new ReversiException("username already used");
		}
		auto user = new User();
		user.username = username;
		user.password = password;  // TODO: password encryption
		user.rating = 0;
		user.connection = null;
		users[username] = user;
	}

	/**
     * login by username and password
	 * Throws: ReversiException on failed to login
     */
	static User login(Connection conn, string username, string password) {
		if (username !in users || users[username].password != password) {
			throw new ReversiException("login failed");
		}
		if (username in actives) {
			throw new ReversiException("you already logged in");
		}
		auto user = users[username];
		user.connection = conn;

		actives[username] = 1;   // make user active
		return user;
	}

	/**
     * return waiting users
     */
	static User[] getWaitings() {
		User[] us;
		foreach (name, _; waitings) {
			us ~= users[name];
		}
		return us;
	}

	/**
     * return waiting user
     * Throws: Exception on user not found
     */
	static User getWaitingUser(string username) {
		if (username in waitings) {
			return users[username];
		}
		throw new Exception("that user is not on wait mode");
	}

	void logout() {
		if (this.username in actives) {
			actives.remove(this.username);
		}
	}

	void wait() {
		waitings[this.username] = 1;
	}
	void nonwait() {
		if (this.username in waitings)  {
			waitings.remove(this.username);
		}
	}
}


/// TCP Connection
class Connection {
public:
	/// Connection status
	enum State {
		START,
		WAIT_OR_BATTLE,
		WAIT,
		BATTLE,
		OTHERWISE,
	}
	State status;  /// status
	Socket socket;  /// Socket
	User user;     /// connection user
	Battle battle;   /// Battle object

	/// Initializer
	this (Socket socket) {
		this.socket = socket;
		this.user = null;
		this.battle = null;
		this.status = State.OTHERWISE;
	}

	/// called when connection has been started
	void started() {
		socket.emitln(JSONValue(["result": "true"]));
		this.status = State.START;
	}

	/// called when connection has been ended
	void closed() {
		if (battle !is null) {
			battle.dead(user);
		}
		close();
	}

	/// called when socket received
	void recved(JSONValue data) {
		import std.algorithm;
		import std.array;
		try {
			with (State) {
				final switch(status) {
				case START:
					auto username = data["userinfo"]["username"].str();
					auto password = data["userinfo"]["password"].str();
					// login
					if (data["action"].str() == "login") {
						this.user = User.login(this, username, password);
					}
					// register and login
					else if (data["action"].str() == "register") {
						User.register(username, password);
						this.user = User.login(this, username, password);
					}
					else {
						throw new Exception("unknown action:" ~ data["action"].str());
					}
					auto waitings = User.getWaitings();
					JSONValue users = JSONValue[].init;
					foreach (u; waitings) {
						users.array() ~= JSONValue(["name": JSONValue(u.username), "rating": JSONValue(u.rating)]);
					}
					JSONValue json;
					json["result"] = "true";
					json["users"] = users;
					socket.emitln(json);
					this.status = WAIT_OR_BATTLE;
					break;
				case WAIT_OR_BATTLE:
					// battle
					if (data["action"].str() == "battle") {
						auto user = User.getWaitingUser(data["user"].str());
						user.nonwait();
						user.connection.status = BATTLE;
						this.battle = new Battle(this.user, user);
						user.connection.battle = this.battle;
						this.status = BATTLE;
					}
					// wait for battle
					else if (data["action"].str() == "wait") {
						user.wait();
						this.status = WAIT;
					}
					else {
						throw new Exception("unknown action:" ~ data["action"].str());
					}
					break;
				case BATTLE:
					writeln(data);
					this.battle.doAct(user, data);
					break;
				case WAIT:
					break;
				case OTHERWISE:
					break;
				}
			}
		}
		catch (Exception e) {
			JSONValue json;
			json["result"] = "false";
			json["msg"] = e.msg;
			socket.emitln(json);
		}
	}

	/// close connection actively
	void close() {
		if (user !is null) {
			user.logout();
		}
		if (socket.isAlive) {
			socket.close();
		}
	}
}

void main()
{
	import std.stdio;
	import std.string:strip;
	import std.algorithm: map, filter, each, sort, remove;

	// start tcp socket as server
	auto server = new TcpSocket();
	server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
	server.bind(new InternetAddress(8888));
	server.listen(128);

	Connection[] conns;

	auto rset = new SocketSet();
	auto eset = new SocketSet();

	// listen
	while (true) {
		rset.reset();
		rset.add(server);
		conns.filter!((c) => (c.socket !is null)).filter!((c) => c.socket.isAlive()).each!((c) => rset.add(c.socket));

		eset.reset();
		eset.add(server);
		conns.filter!((c) => (c.socket !is null)).filter!((c) => c.socket.isAlive()).each!((c) => eset.add(c.socket));

		Socket.select(rset, null, eset);

		if (eset.isSet(server)) {
			// graceful shutdown
			break;
		}

		Connection[] nextConns = [];
		if (rset.isSet(server)) {
			auto conn = new Connection(server.accept());
			conn.started();
			nextConns ~= conn;
		}

		foreach (i, conn; conns) {
			// 末尾に持ってくるよりこっちのほうが良いっぽい
			if (!conn.socket.isAlive) {
				conn.closed();
				continue;
			}

			if (eset.isSet(conn.socket)) {
				conn.closed();
				continue;
			}

			if (rset.isSet(conn.socket)) {
				ubyte[1024] buf;
				auto r = conn.socket.receive(buf);
				if (r == 0 || r == Socket.ERROR) { 
					conn.closed();
					continue;
				}
				try {
					auto json = parseJSON(buf.asUTF.strip);
					conn.recved(json);
				}
				catch (JSONException) {}
			}

			// 生きてるsocketはここまでたどり着く
			nextConns ~= conn;
		}

		conns = nextConns;
	}
}
