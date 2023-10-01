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

#define PLUGIN_VERSION		  "0.4c"
#define HTTP_DATA_RESPONSE "HTTP/1.0 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Max-Age: 999999\r\nContent-Type: application/json; charset=UTF-8\r\nServer: The Cursed Child\r\nContent-Encoding: none\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s\r\n\r\n"
#define HTTP_CORS_RESPONSE	  "HTTP/1.0 200 OK\r\nContent-Length: 0\r\nConnection: drop\r\nServer: SRCDS/Sourcemod(Non-Compliant)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Max-Age: 999999"

ConVar g_cSocketIP	  = null;
ConVar g_cSocketPort  = null;

ConVar g_cRedTeamName = null;
ConVar g_cBluTeamName = null;

Socket hSocket		  = null;

enum struct ControlPoint
{
    int index;
    int team;
    int locked;
    int useless;
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

enum struct TeamNames
{
    char red[32];
    char blu[32];
}

/////////////
// NATIVES //
/////////////
public Plugin myinfo =
{
    name		= "Expose Round State",
    author		= "Shigbeard",
    description = "Makes server info available via a websocket connection on a specific port (must be set in a CFG file on load)",
    version		= PLUGIN_VERSION,
    url			= ""
}

public void OnPluginStart()
{
    g_cSocketIP	   = CreateConVar("ers_ip", "0.0.0.0", "IP to open socket on. Will respond to HTTP requests, CORS can bite me.", FCVAR_PROTECTED);
    g_cSocketPort  = CreateConVar("ers_port", "27019", "Port to open socket on. Will respond to HTTP requests, CORS can bite me.", FCVAR_PROTECTED);
    g_cBluTeamName = CreateConVar("ers_team_blu", "BLU", "Name of the BLU team", FCVAR_PROTECTED);
    g_cRedTeamName = CreateConVar("ers_team_red", "RED", "Name of the RED team", FCVAR_PROTECTED);
    AutoExecConfig(true, "expose_round_state");
    // CreateConVar("ers_version", PLUGIN_VERSION, "Plugin version", FCVAR_PROTECTED);
    g_cSocketIP.AddChangeHook(ERS_OnConVarChanged);
    g_cSocketPort.AddChangeHook(ERS_OnConVarChanged);
    RegServerCmd("ers_restart", ERS_RestartSocket, "Restarts the socket", 0);
    RegServerCmd("ers_version", ERS_Version, "Prints the version of the plugin", 0);
}

public void OnMapStart()
{
    char ip[16];
    char port[6];
    GetConVarString(g_cSocketIP, ip, sizeof(ip));
    GetConVarString(g_cSocketPort, port, sizeof(port));
    PrintToServer("Broadcasting round state on %s:%s", ip, port);
    ERS_CreateListenSocket();
}

public void OnPluginEnd()
{
    char ip[16];
    char port[6];
    GetConVarString(g_cSocketIP, ip, sizeof(ip));
    GetConVarString(g_cSocketPort, port, sizeof(port));
    PrintToServer("Closing socket");
    delete hSocket;
    // hSocket = null;
}

///////////////////////
// CORE PLUGIN LOGIC //
///////////////////////
void ERS_MainLogic(Socket socket, const char[] receiveData)
{
    // Determine the type of request. If it's an OPTIONS request, respond with the CORS headers only.
    int options = StrContains(receiveData, "OPTIONS", true);
    if (options != -1)	  // This is a CORS options request. Respond with the CORS headers only
    {
        char payload[3086];
        payload = "%s";
        Format(payload, sizeof(payload), HTTP_CORS_RESPONSE);
        socket.Send(payload, sizeof(payload));
        socket.Disconnect();
        // Clean up handles
        delete socket;
    }
    else { // We have an actual request for data
        // Collect info from helper functions
        ArrayList points;	 // Get all Control Points
        points = ERS_GetControlPoints();
        points.SortCustom(ERS_SortPointsByIndex);

        ERSRoundState roundState;	 // Get the Round State
        roundState			   = ERS_RetrieveRoundState();
        // Begin collating this data as JSON_Objects
        JSON_Object data	   = new JSON_Object();	   // Begin coersion into a JSON object
        JSON_Object jsonPoints = new JSON_Object();
        // jsonPoints.Set("points", points);

        // loop through points and add each one to the json object
        for (int i = 0; i < points.Length; i++)
        {
            ControlPoint p;
            points.GetArray(i, p);
            JSON_Object jsonPoint = new JSON_Object();
            jsonPoint.SetInt("team", p.team);
            jsonPoint.SetInt("index", p.index);
            jsonPoint.SetInt("locked", p.locked);
            jsonPoint.SetInt("useless", 0);
            char iAsChar[2];	// null terminator
            IntToString(i, iAsChar, sizeof(iAsChar));
            jsonPoints.SetObject(iAsChar, jsonPoint);
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

        // add team names
        TeamNames teamnames;
        GetConVarString(g_cBluTeamName, teamnames.blu, sizeof(teamnames.blu));
        GetConVarString(g_cRedTeamName, teamnames.red, sizeof(teamnames.red));
        JSON_Object jsonTeams = new JSON_Object();
        jsonTeams.SetString("red", teamnames.red);
        jsonTeams.SetString("blu", teamnames.blu);
        data.SetObject("teams", jsonTeams);

        // begin HTML response
        char response[2048];							  // 2048 buffer is more than enough. Realistically 512 is probably better.
        json_encode(data, response, sizeof(response));	  // Convert json object to string

        char payload[3086];	   // Pracitcally the same deal here, except we're formatting a string along the way.
        Format(payload, sizeof(payload), HTTP_DATA_RESPONSE, strlen(response), response);

        // Send payload, close connection
        socket.Send(payload, strlen(payload));	  // Send the payload, we need to give them the correct length too.
        socket.Disconnect();

        // Clean up handles
        delete socket;
        delete jsonRoundState;
        delete jsonTeams;
        // find all the points in data and delete them
        for (int i = 0; i < points.Length; i++)
        {
            // ControlPoint p;
            // points.GetArray(i, p);
            char iAsChar[2];
            IntToString(i, iAsChar, sizeof(iAsChar));
            delete jsonPoints.GetObject(iAsChar);
        }
        delete jsonPoints;
        delete data;
        delete points;
    }
}

//////////////////
// SOCKET STUFF //
//////////////////
// Create a socket to listen for incoming connections
void ERS_CreateListenSocket()
{
    // check if the handle already has a valid socket
    int	 port = GetConVarInt(g_cSocketPort);
    char ip[16];
    GetConVarString(g_cSocketIP, ip, sizeof(ip));
    hSocket = SocketCreate(SOCKET_TCP, ERS_ErrorHandler);
    SocketBind(hSocket, ip, port);
    SocketListen(hSocket, ERS_SocketHandleIncoming);
}

// Create a Handler for Incoming Connections
void ERS_SocketHandleIncoming(Socket socket, Socket newSocket, const char[] hostname, int remotePort, any arg)
{
    newSocket.SetReceiveCallback(ERS_SocketReceiveData);	  // Mandatory, but unused
    newSocket.SetDisconnectCallback(ERS_SocketDisconnect);	  // Be sure to kill the socket
}

// Create a Handler for disconnecting connections.
void ERS_SocketDisconnect(Socket socket, any arg)
{
    // PrintToServer("Disconnected socket");
    delete socket;
}

// Create a Handler for errors.
void ERS_ErrorHandler(Socket socket, const int errorType, const int errorNum, any arg)
{
    // TODO: Handle errors
    PrintToServer("Socket error: %d %d", errorType, errorNum);
    OnPluginEnd();
    OnMapStart();
}

// Create a handler for Receiving data on an incoming connection.
void ERS_SocketReceiveData(Socket socket, const char[] receiveData, const int dataSize, any arg)
{
    ERS_MainLogic(socket, receiveData);
}

//////////////////
// HELPER FUNCS //
//////////////////
// Gets the round state
ERSRoundState ERS_RetrieveRoundState()
{
    int MatchTimer;
    GetMapTimeLeft(MatchTimer);
    ERSRoundState rs;
    rs.state		   = GameRules_GetRoundState();

    rs.redScore		   = GetTeamScore(2);
    rs.blueScore	   = GetTeamScore(3);
    rs.roundTimerState = TF2_GetRoundTimeLeft(rs.roundTime);
    // rs.matchTimerState = TF2_GetMatchTimeLeft(matchTime);
    rs.matchTimerState = TF2TimerState_NotApplicable;
    rs.matchTime	   = MatchTimer;

    rs.isKoth		   = TF2_GetKothClocks(rs.redTime, rs.bluTime);
    return rs;
}
// Gets all control points
ArrayList ERS_GetControlPoints()
{
    ArrayList points = new ArrayList(sizeof(ControlPoint));
    int		  ent	 = -1;
    while ((ent = FindEntityByClassname(ent, "team_control_point")) > 0)
    {
        ControlPoint p;
        p.index	 = GetEntProp(ent, Prop_Data, "m_iPointIndex");
        p.team	 = GetEntProp(ent, Prop_Data, "m_iTeamNum");
        p.locked = GetEntProp(ent, Prop_Data, "m_bLocked");
        points.PushArray(p);
    }
    return points;
}
// Sorts control points by index
int ERS_SortPointsByIndex(int i1, int i2, Handle array, Handle hndl)
{
    int v1 = view_as<ArrayList>(array).Get(i1, ControlPoint::index);
    int v2 = view_as<ArrayList>(array).Get(i2, ControlPoint::index);
    return v1 - v2;
}
// Hook for when the ip or port convar changes, so we restart the socket
void ERS_OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_cSocketIP || convar == g_cSocketPort)
    {
        OnPluginEnd();
        OnMapStart();
    }
}
// Restart the socket
Action ERS_RestartSocket(int args)
{
    PrintToServer("Restarting the socket");
    OnPluginEnd();
    OnMapStart();
    return Plugin_Handled;
}

Action ERS_Version(int args)
{
    PrintToServer("Expose Round State version %s", PLUGIN_VERSION);
    return Plugin_Handled;
}
