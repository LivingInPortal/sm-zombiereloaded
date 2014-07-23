/*
 * ============================================================================
 *
 *  Zombie:Reloaded
 *
 *  File:           zr-eventmanager.sp
 *  Description:    Implements the Event Manager API.
 *
 *  Copyright (C) 2014  Richard Helgeby
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * ============================================================================
 */

#include <sourcemod>
#include <zombie/core/modulemanager>
#include <zombie/core/eventmanager>

/*____________________________________________________________________________*/

#define PLUGIN_NAME         "Zombie:Reloaded Event Manager"
#define PLUGIN_AUTHOR       "Richard Helgeby"
#define PLUGIN_DESCRIPTION  "Implements the Event Manager API."
#define PLUGIN_VERSION      "1.0.0"
#define PLUGIN_URL          "https://github.com/rhelgeby/sm-zombiereloaded"

public Plugin:myinfo =
{
    name = PLUGIN_NAME,
    author = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = PLUGIN_URL
};

/*____________________________________________________________________________*/

/**
 * ADT Array with references to all events.
 */
new Handle:EventList = INVALID_HANDLE;

/**
 * ADT Trie with mappings of event names to events.
 */
new Handle:EventNameIndex = INVALID_HANDLE;

/**
 * Reference to event being prepared (not fired yet), if any.
 */
new ZMEvent:EventStarted = INVALID_ZM_EVENT;

/*____________________________________________________________________________*/

#include "zombiereloaded/libraries/objectlib"
#include "zombiereloaded/eventmanager/event"
#include "zombiereloaded/eventmanager/natives"

/*____________________________________________________________________________*/

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    PrintToServer("Loading event manager.");
    
    InitAPI();
    return APLRes_Success;
}

/*____________________________________________________________________________*/

public OnPluginStart()
{
    InitializeDataStorage();
    PrintToServer("Event manager loaded.");
}

/*____________________________________________________________________________*/

InitializeDataStorage()
{
    if (EventList == INVALID_HANDLE)
    {
        EventList = CreateArray();
    }
    
    if (EventNameIndex == INVALID_HANDLE)
    {
        EventNameIndex = CreateArray();
    }
}

/*____________________________________________________________________________*/

ZMEvent:AddZMEvent(ZMModule:owner, const String:name[], Handle:forwardRef)
{
    new ZMEvent:event = CreateZMEvent(owner, name, forwardRef);

    AddEventToList(event);    
    AddEventToIndex(event);
    
    return event;
}

/*____________________________________________________________________________*/

RemoveZMEvent(ZMEvent:event, bool:deleteForward = true)
{
    AssertIsValidEvent(event);
    
    // TODO: Unhook event callbacks.
    
    RemoveEventFromList(event);
    RemoveEventFromIndex(event);
    
    DeleteZMEvent(event, deleteForward);
}

/*____________________________________________________________________________*/

AddEventToList(ZMEvent:event)
{
    PushArrayCell(EventList, event);
}

/*____________________________________________________________________________*/

AddEventToIndex(ZMEvent:event)
{
    new String:name[EVENT_STRING_LEN];
    GetZMEventName(event, name, sizeof(name));
    
    SetTrieValue(EventNameIndex, name, event);
}

/*____________________________________________________________________________*/

RemoveEventFromList(ZMEvent:event)
{
    new index = FindValueInArray(EventList, event);
    if (index < 0)
    {
        ThrowError("Event is not in list.");
    }
    
    RemoveFromArray(EventList, index);
}

/*____________________________________________________________________________*/

RemoveEventFromIndex(ZMEvent:event)
{
    new String:name[EVENT_STRING_LEN];
    GetZMEventName(event, name, sizeof(name));
    
    RemoveFromTrie(EventNameIndex, name);
}

/*____________________________________________________________________________*/

bool:EventExists(const String:name[])
{
    return GetEventByName(name) != INVALID_ZM_EVENT;
}

/*____________________________________________________________________________*/

ZMEvent:GetEventByName(const String:name[])
{
    new ZMEvent:event = INVALID_ZM_EVENT;
    if (GetTrieValue(EventNameIndex, name, event))
    {
        return event;
    }
    
    return INVALID_ZM_EVENT;
}

/*____________________________________________________________________________*/

GetHexString(any:value, String:buffer[], maxlen)
{
    Format(buffer, maxlen, "%x", value);
}

/*____________________________________________________________________________*/

Function:GetModuleCallback(ZMEvent:event, ZMModule:module)
{
    new Function:callback = INVALID_FUNCTION;
    
    decl String:moduleIdString[16];
    GetHexString(module, moduleIdString, sizeof(moduleIdString));
    
    new Handle:callbacks = GetZMEventCallbacks(event);
    if (GetTrieValue(callbacks, moduleIdString, callback))
    {
        return callback;
    }
    
    return INVALID_FUNCTION;
}

/*____________________________________________________________________________*/

public Handle:StartEvent(ZMEvent:event)
{
    AssertIsValidEvent(event);
    AssertEventNotStarted();
    
    new Handle:forwardRef = GetZMEventForward(event);
    
    Call_StartForward(forwardRef);
    EventStarted = event;
    
    return forwardRef;
}

/*____________________________________________________________________________*/

StartSingleEvent(ZMEvent:event, ZMModule:module)
{
    AssertIsValidEvent(event);
    AssertEventNotStarted();
    
    new Handle:eventOwnerPlugin = ZM_GetModuleOwner(module);
    
    new Function:callback = GetModuleCallback(event, module);
    AssertModuleCallbackValid(callback, event, module);
    
    Call_StartFunction(eventOwnerPlugin, callback);
    EventStarted = event;
}

/*____________________________________________________________________________*/

FireZMEvent(&any:result = 0)
{
    AssertEventStarted();
    
    // Reset before calling, in case of nested events.
    EventStarted = INVALID_ZM_EVENT;
    
    return Call_Finish(result);
}

/*____________________________________________________________________________*/

CancelEvent()
{
    AssertEventStarted();
    
    Call_Cancel();
    EventStarted = INVALID_ZM_EVENT;
}

/*____________________________________________________________________________*/

AssertEventNameNotExists(const String:name[])
{
    if (EventExists(name))
    {
        ThrowNativeError(SP_ERROR_ABORTED, "Event name is already in use: %s", name);
    }
}

/*____________________________________________________________________________*/

AssertEventNameNotEmpty(const String:name[])
{
    if (strlen(name) == 0)
    {
        ThrowNativeError(SP_ERROR_ABORTED, "Event name is empty.");
    }
}

/*____________________________________________________________________________*/

AssertIsEventOwner(ZMModule:module, ZMEvent:event)
{
    if (GetZMEventOwner(event) != module)
    {
        ThrowNativeError(SP_ERROR_ABORTED, "This module does not own the specified event: %x", event);
    }
}

/*____________________________________________________________________________*/

AssertIsValidForward(Handle:forwardRef)
{
    if (forwardRef == INVALID_HANDLE)
    {
        ThrowNativeError(SP_ERROR_ABORTED, "Invalid forward: %x", forwardRef);
    }
}

/*____________________________________________________________________________*/

AssertEventStarted()
{
    if (EventStarted == INVALID_ZM_EVENT)
    {
        ThrowNativeError(SP_ERROR_ABORTED, "No event is started.");
    }
}

/*____________________________________________________________________________*/

AssertEventNotStarted()
{
    if (EventStarted != INVALID_ZM_EVENT)
    {
        ThrowNativeError(SP_ERROR_ABORTED, "An event is already started, but not fired or canceled.");
    }
}

/*____________________________________________________________________________*/

AssertModuleCallbackValid(Function:callback, ZMEvent:event, ZMModule:module)
{
    if (callback == INVALID_FUNCTION)
    {
        ThrowNativeError(SP_ERROR_ABORTED, "The specified module (%x) has not hooked this event (%x).", module, event);
    }
}
