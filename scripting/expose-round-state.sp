// Expose Round State
// Makes server info available via a websocket connection on a specific port (must be set in a CFG file on load)

#include <sourcemod>
#include <sdktools>
#include <socket>
#include <handles>
#include <json>
#include <tf2>
#include <tf2_stocks>
#include <tf2_morestocks>

#define PLUGIN_VERSION		  "0.3"
#define HTTP_RESPONSE_HEADERS "HTTP/1.0 200 OK\r\nContent-Type: application/json; charset=UTF-8\r\nServer: The Cursed Child\r\nContent-Encoding: none\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s\r\n\r\n"
#define HTTP_FUCK_OFF_CORS "HTTP/1.0 200 OK\r\nContent-Length: 0\r\nConnection: drop\r\nServer: SRCDS/Sourcemod(Non-Compliant)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Max-Age: 999999" // Fuck you CORS i HATE YOU I HATE you i HATE YOU I HATE YOU I HATE YOU
// YOU ARE THE SINGLE WORST FUCKING EXCUSE OF AN XSS SHIELD THERE EVER FUCKING EXISTED
// ALL I NEED TO DO IS INJECT HEADERS INTO MY BROWSER TO SAY "YUP THIS REQUEST IS GOOD" and YOU HAVE NO FUCKING CLUE
// THAT I DID THAT.
// FUCKING DUMB FUCK OFF

ConVar g_cSocketIP	 = null;
ConVar g_cSocketPort = null;

Socket hSocket		 = null;

enum struct ControlPoint
{
    int index;
    int team;
}

enum struct ERSRoundState
{
    RoundState	  state;
    int			  redScore;
    int			  blueScore;
    TF2TimerState isKoth;
    TF2TimerState roundTimerState;
    int			  roundTime;
    TF2TimerState matchTimerState;
    int			  matchTime;
    int			  redTime;
    int			  bluTime;
}

public Plugin myinfo =
{
    name		= "Expose Round State",
    author		= "Shigbeard",
    description = "Makes server info available via a websocket connection on a specific port (must be set in a CFG file on load)",
    version		= PLUGIN_VERSION,
    url			= ""


}

public void
    OnPluginStart()
{
    CreateConVar("ers_version", PLUGIN_VERSION, "Plugin version", FCVAR_PROTECTED);
    g_cSocketIP	  = CreateConVar("ers_ip", "0.0.0.0", "IP to open socket on. Will respond to HTTP requests, CORS can bite me.", FCVAR_PROTECTED);
    g_cSocketPort = CreateConVar("ers_port", "27019", "Port to open socket on. Will respond to HTTP requests, CORS can bite me.", FCVAR_PROTECTED);
    AutoExecConfig(true, "expose_round_state");
    RegServerCmd("ers_testcaps", Command_TestCaps, "Test capabilities of the plugin", 0);
}

// Create socket (SocketCreate)
// Bind to port (SocketBind)
// Make it listen (SocketListen) <-- callback function SocketIncomingCB
// Handle incoming connections (SocketConnect) <-- callback function SocketConnectCB
// Respond with game state info (TODO)

Action Command_TestCaps(int args)
{
    return Plugin_Handled;
}

void Disconnect(Socket socket, any arg)
{
    // PrintToServer("Disconnected socket");
    CloseHandle(socket);
}

void ReceiveData(Socket socket, const char[] receiveData, const int dataSize, any arg)
{
    // PrintToServer("Received data: %s", receiveData);

    int options = StrContains(receiveData, "OPTIONS", true);
    // int get		= StrContains(receiveData, "GET", true);

    if (options != -1)
    {
        char payload[3086];	   // Pracitcally the same deal here, except we're formatting a string along the way.
        payload = "%s";
        Format(payload, sizeof(payload), HTTP_FUCK_OFF_CORS);
        socket.Send(payload, sizeof(payload));
        socket.Disconnect();
        CloseHandle(socket);
    }
    else {
        ArrayList points;	 // Get all Control Points
        points = GetControlPoints();
        points.SortCustom(SortPointsByIndex);

        ERSRoundState roundState;	 // Get the Round State
        roundState			   = RetrieveRoundState();

        JSON_Object data	   = new JSON_Object();	   // Begin coersion into a JSON object
        JSON_Object jsonPoints = new JSON_Object();

        // loop through points and add each one to the json object
        for (int i = 0; i < points.Length; i++)
        {
            ControlPoint p;
            points.GetArray(i, p);
            JSON_Object jsonPoint = new JSON_Object();
            jsonPoint.SetInt("team", p.team);
            jsonPoint.SetInt("index", p.index);
            char iAsChar[2];	// null terminator
            IntToString(i, iAsChar, sizeof(iAsChar));
            jsonPoints.SetObject(iAsChar, jsonPoint);

            // Cannot delete jsonPoint because we store a reference to it.
        }
        data.SetObject("points", jsonPoints);

        // add round state
        JSON_Object jsonRoundState = new JSON_Object();
        jsonRoundState.SetInt("state", view_as<int>(roundState.state));
        jsonRoundState.SetInt("redScore", view_as<int>(roundState.redScore));
        jsonRoundState.SetInt("blueScore", view_as<int>(roundState.blueScore));
        jsonRoundState.SetInt("isKoth", view_as<int>(roundState.isKoth));
        jsonRoundState.SetInt("roundTimerState", view_as<int>(roundState.roundTimerState));
        jsonRoundState.SetInt("roundTime", view_as<int>(roundState.roundTime));
        jsonRoundState.SetInt("matchTimerState", view_as<int>(roundState.matchTimerState));
        jsonRoundState.SetInt("matchTime", view_as<int>(roundState.matchTime));
        jsonRoundState.SetInt("redTime", view_as<int>(roundState.redTime));
        jsonRoundState.SetInt("bluTime", view_as<int>(roundState.bluTime));
        data.SetObject("roundState", jsonRoundState);

        // begin HTML response
        char response[2048];							  // 2048 buffer is more than enough. Realistically 512 is probably better.
        json_encode(data, response, sizeof(response));	  // Convert json object to string

        char payload[3086];	   // Pracitcally the same deal here, except we're formatting a string along the way.
        Format(payload, sizeof(payload), HTTP_RESPONSE_HEADERS, strlen(response), response);

        socket.Send(payload, strlen(payload));	  // Send the payload, we need to give them the correct length too.
        socket.Disconnect();
        CloseHandle(socket);
    }
}

void HandleIncoming(Socket socket, Socket newSocket, const char[] hostname, int remotePort, any arg)
{
    // An incoming connection, on newSocket, has come in.
    newSocket.SetReceiveCallback(ReceiveData);		// Mandatory, but unused
    newSocket.SetDisconnectCallback(Disconnect);	// Be sure to kill the socket

    // CloseHandle(newSocket); // All Sockets are Handles, and must be Closed. Memory leaks onto the carpet otherwise.
}

ERSRoundState RetrieveRoundState()
{
    ERSRoundState rs;
    rs.state		   = GameRules_GetRoundState();

    rs.redScore		   = GetTeamScore(2);
    rs.blueScore	   = GetTeamScore(3);
    rs.roundTimerState = TF2_GetRoundTimeLeft(rs.roundTime);
    // rs.matchTimerState = TF2_GetMatchTimeLeft(matchTime);
    rs.matchTimerState = TF2TimerState_NotApplicable;
    rs.matchTime	   = 0;

    rs.isKoth		   = TF2_GetKothClocks(rs.redTime, rs.bluTime);
    return rs;
}

ArrayList GetControlPoints()
{
    ArrayList points = new ArrayList(sizeof(ControlPoint));
    int		  ent	 = -1;
    while ((ent = FindEntityByClassname(ent, "team_control_point")) > 0)
    {
        ControlPoint p;
        p.index = GetEntProp(ent, Prop_Data, "m_iPointIndex");
        p.team	= GetEntProp(ent, Prop_Data, "m_iTeamNum");
        points.PushArray(p);
    }
    return points;
}

void ErrorHandler(Socket socket, const int errorType, const int errorNum, any arg)
{
    // PrintToServer("Error: %d, %d", errorType, errorNum);
}

void CreateListenServer()
{
    // check if the handle already has a valid socket
    if (hSocket != null)
    {
        // PrintToServer("Socket already exists");
        return;
    }
    int	 port = GetConVarInt(g_cSocketPort);
    char ip[16];
    GetConVarString(g_cSocketIP, ip, sizeof(ip));
    hSocket = SocketCreate(SOCKET_TCP, ErrorHandler);
    SocketBind(hSocket, ip, port);
    SocketListen(hSocket, HandleIncoming);
}

public void OnMapStart()
{
    CreateListenServer();
}

public void OnPluginEnd()
{
    // SocketDisconnect(hSocket);
    CloseHandle(hSocket);
    // hSocket = null;
}

int SortPointsByIndex(int i1, int i2, Handle array, Handle hndl)
{
    int v1 = view_as<ArrayList>(array).Get(i1, ControlPoint::index);
    int v2 = view_as<ArrayList>(array).Get(i2, ControlPoint::index);
    return v1 - v2;
}
