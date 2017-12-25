import std.socket;
import std.stdio;
import std.json;
import util;

class ReversiException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
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

	void logout() {
		this.connection = null;
		actives.remove(this.username);
	}
}


/// TCP Connection
class Connection {
public:
	/// Connection status
	enum State {
		START,
		SEARCH,
		OTHERWISE,
	}
	State status;  /// status
	Socket socket;  /// Socket
	User user;     /// connection user;

	/// Initializer
	this (Socket socket) {
		this.socket = socket;
		this.user = null;
		this.status = State.OTHERWISE;
	}

	/// called when connection has been started
	void started() {
		socket.emitln(JSONValue(["result": "true"]));
		this.status = State.START;
	}

	/// called when connection has been ended
	void closed() {
		writeln("end");
	}

	/// called when socket received
	void recved(JSONValue data) {
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
					break;
				case SEARCH:
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
		socket.close();
	}
}

void main()
{
	import std.stdio;
	import std.string:strip;
	import std.algorithm:each, sort, remove;

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
		conns.each!((c) => rset.add(c.socket));

		eset.reset();
		eset.add(server);
		conns.each!((c) => eset.add(c.socket));

		Socket.select(rset, null, eset);

		if (eset.isSet(server)) {
			// graceful shutdown
			break;
		}

		if (rset.isSet(server)) {
			auto conn = new Connection(server.accept());
			conn.started();
			conns ~= conn;
		}

		ulong[] rmlist;
		foreach (i, conn; conns) {
			if (eset.isSet(conn.socket)) {
				conn.close();
				rmlist ~= i;
				continue;
			}

			if (rset.isSet(conn.socket)) {
				ubyte[1024] buf;
				auto r = conn.socket.receive(buf);
				if (r == 0 || r == Socket.ERROR) { 
					conn.close();
					rmlist ~= i;
					continue;
				}
				try {
					auto json = parseJSON(buf.asUTF.strip);
					conn.recved(json);
				}
				catch (JSONException) {}
			}

			if (! conn.socket.isAlive) {
				conn.closed();
				rmlist ~= i;
			}
		}

		foreach (i; rmlist.sort!"a > b") {
			conns = conns.remove(i);
		}
	}
}
