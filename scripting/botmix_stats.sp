#pragma semicolon 1
#pragma newdecls required

#include <botmix>
#include <lvl_ranks>

Database hDatabase;

#define COL_NAME       "name"
#define COL_EXP        "value"      // очки
#define COL_PLAYTIME   "playtime"   // секунды

ConVar cvTableName;

char sFile[512];

public Plugin myinfo = 
{
	name = "[BotMiX] Lvl rank stats",
	author = "Nek.'a 2x2 | vk.com/nekromio | t.me/sourcepwn ",
	description = "Сбор статистики",
	version = "1.0.0 101",
	url = "ggwp.site | vk.com/nekromio | t.me/sourcepwn "
};

public void OnPluginStart()
{
    cvTableName = CreateConVar("sm_botmixlvl_table_name", "lvl_base", "Имя таблицы базы данных статистики");

    AutoExecConfig(true, "lvl_rank", "botmix");

    BuildPath(Path_SM, sFile, sizeof(sFile), "logs/botmix.log");

    BotMix_HookEvent(BOTMIX_REQUEST_GET_SERVER_TOP, OnGetStatsTop);
    BotMix_HookEvent(BOTMIX_REQUEST_GET_RANK_PLAYER, OnGetStatsRankPlayer);
}

public void LogToFileOnly(const char[] path, const char[] format, any ...)
{
    char buffer[512];
    VFormat(buffer, sizeof(buffer), format, 3);

    char sDate[32];
    FormatTime(sDate, sizeof(sDate), "%Y:%m:%d %H:%M:%S");

    char final[600];
    Format(final, sizeof(final), "%s | %s", sDate, buffer);

    File hFile = OpenFile(path, "a");
    if (hFile != null)
    {
        WriteFileLine(hFile, final);
        delete hFile;
    }
    else
    {
        LogError("Failed to open file: %s", path);
    }
}

public void OnConfigsExecuted()
{
    hDatabase = LR_GetDatabase();
    if(hDatabase == null)
	{
		CreateTimer(2.0, Timer_Reconnect, _, TIMER_REPEAT);
	}
}

public Action Timer_Reconnect(Handle hTimer)
{
	hDatabase = LR_GetDatabase();
	if(hDatabase == null)
		LogMessage("Попытке переподключения");
	else
		return Plugin_Stop;
	return Plugin_Continue;
}

public void OnGetStatsTop(KeyValues kv)
{
    if(hDatabase == null)
        return;
    int chat_id = kv.GetNum("chat_id");
    LogToFileOnly(sFile, "[OnGetStatsTop] Переданный chat_id %d", chat_id);
    ShowTopAllToChat(chat_id);
}

void ShowTopAllToChat(int chat_id, int limit = 10)
{
    if (hDatabase == null)
    {
        LogError("[LR] DB null");
        return;
    }

    char sTableName[64];
    cvTableName.GetString(sTableName, sizeof(sTableName));
    LogToFileOnly(sFile, "[ShowTopAllToChat] Переданный chat_id %d", chat_id);
    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT %s, %s, playtime FROM `%s` ORDER BY %s DESC LIMIT %d;",
        COL_NAME, COL_EXP, sTableName, COL_EXP, limit);

    hDatabase.Query(GetTop_Callback, query, chat_id);
}

public void GetTop_Callback(Database database, DBResultSet hResult, const char[] error, any chat_id)
{
    if (error[0])
    {
        LogError("[LR] Top_AllChat: %s", error);
        return;
    }

    char places[1024];
    char names[4096];
    char hoursStr[2048];
    char expsStr[2048];

    places[0] = names[0] = hoursStr[0] = expsStr[0] = '\0';

    char name[64];
    char buf[32];
    int place = 0;

    while (hResult.FetchRow())
    {
        place++;

        hResult.FetchString(0, name, sizeof(name));
        int exp      = hResult.FetchInt(1);
        int playtime = hResult.FetchInt(2);      // секунды
        int hours    = playtime / 3600;     // целые часы

        if (place > 1)
        {
            StrCat(places,   sizeof(places),   ",");
            StrCat(names,    sizeof(names),    ",");
            StrCat(hoursStr, sizeof(hoursStr), ",");
            StrCat(expsStr,  sizeof(expsStr),  ",");
        }

        IntToString(place, buf, sizeof(buf));
        StrCat(places, sizeof(places), buf);

        ReplaceString(name, sizeof(name), ",", " ");
        StrCat(names, sizeof(names), name);

        IntToString(hours, buf, sizeof(buf));
        StrCat(hoursStr, sizeof(hoursStr), buf);

        IntToString(exp, buf, sizeof(buf));
        StrCat(expsStr, sizeof(expsStr), buf);
    }

    if (!place)
    {
        LogMessage("[LR] Top_AllChat: нет данных для топа (chat_id: %d)", chat_id);
        return;
    }
    LogToFileOnly(sFile, "[GetTop_Callback] Переданный chat_id %d", chat_id);
    KeyValues kv = new KeyValues("botmix_send_stats_top");
    kv.SetNum("chat_id", chat_id);
    kv.SetString("place",   places);
    kv.SetString("name",    names);
    kv.SetString("hours",   hoursStr);
    kv.SetString("exp",     expsStr);
    BotMix_TriggerEvent(BOTMIX_REQUEST_SEND_SERVER_TOP, kv);
    delete kv;
}

public void OnGetStatsRankPlayer(KeyValues kv)
{
    //LogToFileOnly(sFile, "Вызов ранга");
    if(hDatabase == null)
        return;

    char steam[32];
    kv.GetString("steam", steam, sizeof(steam));
    int chat_id = kv.GetNum("chat_id");
    ShowRankPlayer(chat_id, steam);
}

void ShowRankPlayer(int chat_id, const char[] steam)
{
    if (hDatabase == null)
    {
        LogError("[LR] DB null");
        return;
    }

    char sTableName[64];
    cvTableName.GetString(sTableName, sizeof(sTableName));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT steam, name, value, rank, kills, deaths, shoots, hits, headshots, \
        assists, round_win, round_lose, playtime \
        FROM `%s` WHERE steam = '%s' LIMIT 1;",
        sTableName, steam);

    DataPack hPack = new DataPack();
    hPack.WriteCell(chat_id);
    hPack.WriteString(steam);
    hDatabase.Query(ShowRankPlayer_Callback, query, hPack);
}

public void ShowRankPlayer_Callback(Database db, DBResultSet rs, const char[] err, DataPack hPack)
{
    hPack.Reset();

    char requestedSteam[64];

    int chat_id = hPack.ReadCell();
    hPack.ReadString(requestedSteam, sizeof(requestedSteam));
    delete hPack;

    if (err[0])
    {
        LogError("[LR] Top_OnePlayerCb: %s", err);
        return;
    }

    bool found = rs.FetchRow();

    char steam[64];
    char name[64];

    int value, rank, kills, deaths, shoots, hits, headshots, assists;
    int roundWin, roundLose, playtime, hours;

    if (found)
    {
        rs.FetchString(0, steam, sizeof(steam));   // steam
        rs.FetchString(1, name,  sizeof(name));    // name
        value     = rs.FetchInt(2);
        rank      = rs.FetchInt(3);
        kills     = rs.FetchInt(4);
        deaths    = rs.FetchInt(5);
        shoots    = rs.FetchInt(6);
        hits      = rs.FetchInt(7);
        headshots = rs.FetchInt(8);
        assists   = rs.FetchInt(9);
        roundWin  = rs.FetchInt(10);
        roundLose = rs.FetchInt(11);
        playtime  = rs.FetchInt(12);

        hours = playtime / 3600;
        ReplaceString(name, sizeof(name), ",", " ");
    }
    else
    {
        // нет записи - но всё равно что-то шлём
        strcopy(steam, sizeof(steam), requestedSteam);
        //strcopy(name, sizeof(name), "Неизвестно");

        value = rank = kills = deaths = shoots = hits = headshots = assists = 0;
        roundWin = roundLose = playtime = hours = 0;

        //LogMessage("[LR] Top_OnePlayerCb: игрок не найден (chatName: %s, steam: %s)", chatName, requestedSteam);
    }

    KeyValues kv = new KeyValues("botmix_send_stats_player");
    kv.SetNum("chat_id",  chat_id);
    kv.SetString("steam",     steam);
    kv.SetString("name",      name);

    kv.SetNum("value",        value);
    kv.SetNum("rank",         rank);
    kv.SetNum("kills",        kills);
    kv.SetNum("deaths",       deaths);
    kv.SetNum("shoots",       shoots);
    kv.SetNum("hits",         hits);
    kv.SetNum("headshots",    headshots);
    kv.SetNum("assists",      assists);
    kv.SetNum("round_win",    roundWin);
    kv.SetNum("round_lose",   roundLose);
    kv.SetNum("playtime",     playtime);
    kv.SetNum("hours",        hours);

    // спец-переменная для BotMix
    kv.SetNum("has_stats",    found ? 1 : 0);

    BotMix_TriggerEvent(BOTMIX_REQUEST_SEND_RANK_PLAYER, kv);
    delete kv;
}
