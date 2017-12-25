import std.socket;
import std.stdio;
import util;

/// User
class User {
public:
	static User[string] users;    /// all user list
	static int[string] waitings;  /// usernames who waiting for battle 

	string username;   /// username[unique]
	string password;   /// password
	ulong rating;      /// rating
}

/// TCP Connection
class Connection {
public:
	Socket socket;  /// Socket

	/// Initializer
	this (Socket socket) {
		this.socket = socket;
	}

	/// called when connection has been started
	void start() {
		writeln("start");
	}

	/// called when connection has been ended
	void close() {
		writeln("end");
	}

	/// called when socket received
	void recv(string data) {
		writeln("recv: " ~ data);
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
			conn.start();
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
				conn.recv(buf.asUTF.strip);
			}

			if (! conn.socket.isAlive) {
				conn.close();
				rmlist ~= i;
			}
		}

		foreach (i; rmlist.sort!"a > b") {
			conns = conns.remove(i);
		}
	}
}
