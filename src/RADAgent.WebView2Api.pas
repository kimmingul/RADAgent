unit RADAgent.WebView2Api;

{ The WebView2 COM interfaces the chat uses, declared here so the package does not depend on the
  Winapi.WebView2 unit of one RAD Studio release (its content differs between 10.4, 11, 12 and
  13). Layout follows Microsoft's WebView2.h: every interface lists all of its methods in vtable
  order; the ones RADAgent never calls are placeholders without parameters, which keeps the
  slots right without declaring the types they take. No VCL, no ToolsAPI. }

interface

uses
  Winapi.Windows;

type
  wireHWND = HWND;
  COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND = LongWord;
  COREWEBVIEW2_MOVE_FOCUS_REASON = LongWord;

  tagRECT = record
    Left: Integer;
    Top: Integer;
    Right: Integer;
    Bottom: Integer;
  end;

  COREWEBVIEW2_COLOR = packed record
    A: Byte;
    R: Byte;
    G: Byte;
    B: Byte;
  end;

  EventRegistrationToken = record
    Value: Int64;
  end;

const
  COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS = 2;
  COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC = 0;

type
  ICoreWebView2EnvironmentOptions = interface;
  ICoreWebView2Settings = interface;
  ICoreWebView2Settings2 = interface;
  ICoreWebView2Settings3 = interface;
  ICoreWebView2WebMessageReceivedEventArgs = interface;
  ICoreWebView2NavigationStartingEventArgs = interface;
  ICoreWebView2NewWindowRequestedEventArgs = interface;
  ICoreWebView2 = interface;
  ICoreWebView2_2 = interface;
  ICoreWebView2_3 = interface;
  ICoreWebView2Controller = interface;
  ICoreWebView2Controller2 = interface;
  ICoreWebView2Environment = interface;
  ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler = interface;
  ICoreWebView2CreateCoreWebView2ControllerCompletedHandler = interface;
  ICoreWebView2WebMessageReceivedEventHandler = interface;
  ICoreWebView2NavigationStartingEventHandler = interface;
  ICoreWebView2NewWindowRequestedEventHandler = interface;

  ICoreWebView2EnvironmentOptions = interface(IUnknown)
    ['{2FDE08A8-1E9A-4766-8C05-95A9CEB9D1C5}']
    function Get_AdditionalBrowserArguments: HResult; stdcall;
    function Set_AdditionalBrowserArguments: HResult; stdcall;
    function Get_Language: HResult; stdcall;
    function Set_Language: HResult; stdcall;
    function Get_TargetCompatibleBrowserVersion: HResult; stdcall;
    function Set_TargetCompatibleBrowserVersion: HResult; stdcall;
    function Get_AllowSingleSignOnUsingOSPrimaryAccount: HResult; stdcall;
    function Set_AllowSingleSignOnUsingOSPrimaryAccount: HResult; stdcall;
  end;
  ICoreWebView2Settings = interface(IUnknown)
    ['{E562E4F0-D7FA-43AC-8D71-C05150499F00}']
    function Get_IsScriptEnabled: HResult; stdcall;
    function Set_IsScriptEnabled: HResult; stdcall;
    function Get_IsWebMessageEnabled: HResult; stdcall;
    function Set_IsWebMessageEnabled: HResult; stdcall;
    function Get_AreDefaultScriptDialogsEnabled: HResult; stdcall;
    function Set_AreDefaultScriptDialogsEnabled: HResult; stdcall;
    function Get_IsStatusBarEnabled: HResult; stdcall;
    function Set_IsStatusBarEnabled(IsStatusBarEnabled: Integer): HResult; stdcall;
    function Get_AreDevToolsEnabled: HResult; stdcall;
    function Set_AreDevToolsEnabled(AreDevToolsEnabled: Integer): HResult; stdcall;
    function Get_AreDefaultContextMenusEnabled: HResult; stdcall;
    function Set_AreDefaultContextMenusEnabled: HResult; stdcall;
    function Get_AreHostObjectsAllowed: HResult; stdcall;
    function Set_AreHostObjectsAllowed(allowed: Integer): HResult; stdcall;
    function Get_IsZoomControlEnabled: HResult; stdcall;
    function Set_IsZoomControlEnabled: HResult; stdcall;
    function Get_IsBuiltInErrorPageEnabled: HResult; stdcall;
    function Set_IsBuiltInErrorPageEnabled: HResult; stdcall;
  end;
  ICoreWebView2Settings2 = interface(ICoreWebView2Settings)
    ['{EE9A0F68-F46C-4E32-AC23-EF8CAC224D2A}']
    function Get_UserAgent: HResult; stdcall;
    function Set_UserAgent: HResult; stdcall;
  end;
  ICoreWebView2Settings3 = interface(ICoreWebView2Settings2)
    ['{FDB5AB74-AF33-4854-84F0-0A631DEB5EBA}']
    function Get_AreBrowserAcceleratorKeysEnabled: HResult; stdcall;
    function Set_AreBrowserAcceleratorKeysEnabled(value: Integer): HResult; stdcall;
  end;
  ICoreWebView2WebMessageReceivedEventArgs = interface(IUnknown)
    ['{0F99A40C-E962-4207-9E92-E3D542EFF849}']
    function Get_Source: HResult; stdcall;
    function Get_webMessageAsJson(out value: PWideChar): HResult; stdcall;
    function TryGetWebMessageAsString: HResult; stdcall;
  end;
  ICoreWebView2NavigationStartingEventArgs = interface(IUnknown)
    ['{5B495469-E119-438A-9B18-7604F25F2E49}']
    function Get_uri(out uri: PWideChar): HResult; stdcall;
    function Get_IsUserInitiated: HResult; stdcall;
    function Get_IsRedirected: HResult; stdcall;
    function Get_RequestHeaders: HResult; stdcall;
    function Get_Cancel: HResult; stdcall;
    function Set_Cancel(Cancel: Integer): HResult; stdcall;
    function Get_NavigationId: HResult; stdcall;
  end;
  ICoreWebView2NewWindowRequestedEventArgs = interface(IUnknown)
    ['{34ACB11C-FC37-4418-9132-F9C21D1EAFB9}']
    function Get_uri(out uri: PWideChar): HResult; stdcall;
    function Set_NewWindow: HResult; stdcall;
    function Get_NewWindow: HResult; stdcall;
    function Set_Handled(Handled: Integer): HResult; stdcall;
    function Get_Handled: HResult; stdcall;
    function Get_IsUserInitiated: HResult; stdcall;
    function GetDeferral: HResult; stdcall;
    function Get_WindowFeatures: HResult; stdcall;
  end;
  ICoreWebView2 = interface(IUnknown)
    ['{76ECEACB-0462-4D94-AC83-423A6793775E}']
    function Get_Settings(out Settings: ICoreWebView2Settings): HResult; stdcall;
    function Get_Source: HResult; stdcall;
    function Navigate(uri: PWideChar): HResult; stdcall;
    function NavigateToString: HResult; stdcall;
    function add_NavigationStarting(const eventHandler: ICoreWebView2NavigationStartingEventHandler; out token: EventRegistrationToken): HResult; stdcall;
    function remove_NavigationStarting: HResult; stdcall;
    function add_ContentLoading: HResult; stdcall;
    function remove_ContentLoading: HResult; stdcall;
    function add_SourceChanged: HResult; stdcall;
    function remove_SourceChanged: HResult; stdcall;
    function add_HistoryChanged: HResult; stdcall;
    function remove_HistoryChanged: HResult; stdcall;
    function add_NavigationCompleted: HResult; stdcall;
    function remove_NavigationCompleted: HResult; stdcall;
    function add_FrameNavigationStarting: HResult; stdcall;
    function remove_FrameNavigationStarting: HResult; stdcall;
    function add_FrameNavigationCompleted: HResult; stdcall;
    function remove_FrameNavigationCompleted: HResult; stdcall;
    function add_ScriptDialogOpening: HResult; stdcall;
    function remove_ScriptDialogOpening: HResult; stdcall;
    function add_PermissionRequested: HResult; stdcall;
    function remove_PermissionRequested: HResult; stdcall;
    function add_ProcessFailed: HResult; stdcall;
    function remove_ProcessFailed: HResult; stdcall;
    function AddScriptToExecuteOnDocumentCreated: HResult; stdcall;
    function RemoveScriptToExecuteOnDocumentCreated: HResult; stdcall;
    function ExecuteScript: HResult; stdcall;
    function CapturePreview: HResult; stdcall;
    function Reload: HResult; stdcall;
    function PostWebMessageAsJson(webMessageAsJson: PWideChar): HResult; stdcall;
    function PostWebMessageAsString: HResult; stdcall;
    function add_WebMessageReceived(const handler: ICoreWebView2WebMessageReceivedEventHandler; out token: EventRegistrationToken): HResult; stdcall;
    function remove_WebMessageReceived: HResult; stdcall;
    function CallDevToolsProtocolMethod: HResult; stdcall;
    function Get_BrowserProcessId: HResult; stdcall;
    function Get_CanGoBack: HResult; stdcall;
    function Get_CanGoForward: HResult; stdcall;
    function GoBack: HResult; stdcall;
    function GoForward: HResult; stdcall;
    function GetDevToolsProtocolEventReceiver: HResult; stdcall;
    function Stop: HResult; stdcall;
    function add_NewWindowRequested(const eventHandler: ICoreWebView2NewWindowRequestedEventHandler; out token: EventRegistrationToken): HResult; stdcall;
    function remove_NewWindowRequested: HResult; stdcall;
    function add_DocumentTitleChanged: HResult; stdcall;
    function remove_DocumentTitleChanged: HResult; stdcall;
    function Get_DocumentTitle: HResult; stdcall;
    function AddHostObjectToScript: HResult; stdcall;
    function RemoveHostObjectFromScript: HResult; stdcall;
    function OpenDevToolsWindow: HResult; stdcall;
    function add_ContainsFullScreenElementChanged: HResult; stdcall;
    function remove_ContainsFullScreenElementChanged: HResult; stdcall;
    function Get_ContainsFullScreenElement: HResult; stdcall;
    function add_WebResourceRequested: HResult; stdcall;
    function remove_WebResourceRequested: HResult; stdcall;
    function AddWebResourceRequestedFilter: HResult; stdcall;
    function RemoveWebResourceRequestedFilter: HResult; stdcall;
    function add_WindowCloseRequested: HResult; stdcall;
    function remove_WindowCloseRequested: HResult; stdcall;
  end;
  ICoreWebView2_2 = interface(ICoreWebView2)
    ['{9E8F0CF8-E670-4B5E-B2BC-73E061E3184C}']
    function add_WebResourceResponseReceived: HResult; stdcall;
    function remove_WebResourceResponseReceived: HResult; stdcall;
    function NavigateWithWebResourceRequest: HResult; stdcall;
    function add_DOMContentLoaded: HResult; stdcall;
    function remove_DOMContentLoaded: HResult; stdcall;
    function Get_CookieManager: HResult; stdcall;
    function Get_Environment: HResult; stdcall;
  end;
  ICoreWebView2_3 = interface(ICoreWebView2_2)
    ['{A0D6DF20-3B92-416D-AA0C-437A9C727857}']
    function TrySuspend: HResult; stdcall;
    function Resume: HResult; stdcall;
    function Get_IsSuspended: HResult; stdcall;
    function SetVirtualHostNameToFolderMapping(hostName: PWideChar; folderPath: PWideChar; accessKind: COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND): HResult; stdcall;
    function ClearVirtualHostNameToFolderMapping: HResult; stdcall;
  end;
  ICoreWebView2Controller = interface(IUnknown)
    ['{4D00C0D1-9434-4EB6-8078-8697A560334F}']
    function Get_IsVisible: HResult; stdcall;
    function Set_IsVisible(IsVisible: Integer): HResult; stdcall;
    function Get_Bounds: HResult; stdcall;
    function Set_Bounds(Bounds: tagRECT): HResult; stdcall;
    function Get_ZoomFactor: HResult; stdcall;
    function Set_ZoomFactor: HResult; stdcall;
    function add_ZoomFactorChanged: HResult; stdcall;
    function remove_ZoomFactorChanged: HResult; stdcall;
    function SetBoundsAndZoomFactor: HResult; stdcall;
    function MoveFocus(reason: COREWEBVIEW2_MOVE_FOCUS_REASON): HResult; stdcall;
    function add_MoveFocusRequested: HResult; stdcall;
    function remove_MoveFocusRequested: HResult; stdcall;
    function add_GotFocus: HResult; stdcall;
    function remove_GotFocus: HResult; stdcall;
    function add_LostFocus: HResult; stdcall;
    function remove_LostFocus: HResult; stdcall;
    function add_AcceleratorKeyPressed: HResult; stdcall;
    function remove_AcceleratorKeyPressed: HResult; stdcall;
    function Get_ParentWindow: HResult; stdcall;
    function Set_ParentWindow(ParentWindow: wireHWND): HResult; stdcall;
    function NotifyParentWindowPositionChanged: HResult; stdcall;
    function Close: HResult; stdcall;
    function Get_CoreWebView2(out CoreWebView2: ICoreWebView2): HResult; stdcall;
  end;
  ICoreWebView2Controller2 = interface(ICoreWebView2Controller)
    ['{C979903E-D4CA-4228-92EB-47EE3FA96EAB}']
    function Get_DefaultBackgroundColor: HResult; stdcall;
    function Set_DefaultBackgroundColor(value: COREWEBVIEW2_COLOR): HResult; stdcall;
  end;
  ICoreWebView2Environment = interface(IUnknown)
    ['{B96D755E-0319-4E92-A296-23436F46A1FC}']
    function CreateCoreWebView2Controller(ParentWindow: HWND; const handler: ICoreWebView2CreateCoreWebView2ControllerCompletedHandler): HResult; stdcall;
    function CreateWebResourceResponse: HResult; stdcall;
    function Get_BrowserVersionString: HResult; stdcall;
    function add_NewBrowserVersionAvailable: HResult; stdcall;
    function remove_NewBrowserVersionAvailable: HResult; stdcall;
  end;
  ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler = interface(IUnknown)
    ['{4E8A3389-C9D8-4BD2-B6B5-124FEE6CC14D}']
    function Invoke(errorCode: HResult; const result: ICoreWebView2Environment): HResult; stdcall;
  end;
  ICoreWebView2CreateCoreWebView2ControllerCompletedHandler = interface(IUnknown)
    ['{6C4819F3-C9B7-4260-8127-C9F5BDE7F68C}']
    function Invoke(errorCode: HResult; const result: ICoreWebView2Controller): HResult; stdcall;
  end;
  ICoreWebView2WebMessageReceivedEventHandler = interface(IUnknown)
    ['{57213F19-00E6-49FA-8E07-898EA01ECBD2}']
    function Invoke(const sender: ICoreWebView2; const args: ICoreWebView2WebMessageReceivedEventArgs): HResult; stdcall;
  end;
  ICoreWebView2NavigationStartingEventHandler = interface(IUnknown)
    ['{9ADBE429-F36D-432B-9DDC-F8881FBD76E3}']
    function Invoke(const sender: ICoreWebView2; const args: ICoreWebView2NavigationStartingEventArgs): HResult; stdcall;
  end;
  ICoreWebView2NewWindowRequestedEventHandler = interface(IUnknown)
    ['{D4C185FE-C81C-4989-97AF-2D3FA7AB5651}']
    function Invoke(const sender: ICoreWebView2; const args: ICoreWebView2NewWindowRequestedEventArgs): HResult; stdcall;
  end;

implementation

end.
