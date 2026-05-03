import core.sys.windows.windows;
import core.sys.windows.wingdi;
import core.sys.windows.winuser;
import core.stdc.stdio : snprintf;
import core.stdc.wchar_ : swprintf;

enum IDC_MAIN_EDIT   = 101;
enum IDC_BTN_ADD     = 102;
enum IDC_BTN_CLEAR   = 103;
enum IDC_BTN_COLOR   = 104;
enum IDC_LISTBOX     = 105;
enum IDC_LABEL       = 106;
enum IDC_STATUS      = 107;
enum IDC_CHECKBOX    = 108;
enum IDC_RADIO1      = 109;
enum IDC_RADIO2      = 110;
enum IDC_PROGRESS    = 111;
enum IDC_SLIDER      = 112;

enum CLEARTYPE_QUALITY  = 5;
enum TBS_AUTOTICKS      = 0x0001;
enum TBM_SETRANGE       = WM_USER + 6;
enum TBM_SETPOS         = WM_USER + 5;
enum TBM_GETPOS         = WM_USER + 0;
enum PBS_SMOOTH         = 0x01;
enum PBM_SETRANGE       = WM_USER + 1;
enum PBM_SETPOS         = WM_USER + 2;

HINSTANCE hInst;
HWND hMainWnd, hEdit, hBtnAdd, hBtnClear, hBtnColor, hList, hLabel, hStatus;
HWND hCheck, hRadio1, hRadio2, hProgress, hSlider;
HBRUSH hBrushBg;
HFONT hFont;
int itemCounter = 0;
COLORREF customColor = RGB(230, 240, 255);

enum w(wchar[] s) = s ~ cast(wchar)0;

nothrow void intToWStr(int v, wchar* buf, size_t len) {
    char[16] tmp;
    snprintf(tmp.ptr, 16, "%d", v);
    size_t i = 0;
    while (tmp[i] && i < len - 1) { buf[i] = cast(wchar)tmp[i]; i++; }
    buf[i] = 0;
}

extern(Windows) LRESULT WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) nothrow {
    switch (msg) {
    case WM_CREATE:
        createControls(hwnd);
        return 0;

    case WM_COMMAND:
        uint id = LOWORD(wp);
        uint code = HIWORD(wp);
        if (id == IDC_BTN_ADD && code == BN_CLICKED) {
            handleAdd(hwnd);
        } else if (id == IDC_BTN_CLEAR && code == BN_CLICKED) {
            handleClear();
        } else if (id == IDC_BTN_COLOR && code == BN_CLICKED) {
            handleColorPick(hwnd);
        } else if (id == IDC_CHECKBOX && code == BN_CLICKED) {
            handleCheckbox();
        } else if (id == IDC_RADIO1 || id == IDC_RADIO2) {
            handleRadio(id);
        }
        return 0;

    case WM_HSCROLL:
        if (cast(HWND)lp == hSlider) {
            handleSlider();
        }
        return 0;

    case WM_CTLCOLORSTATIC:
        auto hdc = cast(HDC)wp;
        auto hCtrl = cast(HWND)lp;
        if (hCtrl == hLabel || hCtrl == hStatus) {
            SetTextColor(hdc, RGB(30, 30, 80));
            SetBkColor(hdc, customColor);
            return cast(LRESULT)hBrushBg;
        }
        return 0;

    case WM_PAINT:
        handlePaint(hwnd);
        return 0;

    case WM_SIZE:
        handleResize(hwnd);
        return 0;

    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;

    case WM_DESTROY:
        DeleteObject(hBrushBg);
        DeleteObject(hFont);
        PostQuitMessage(0);
        return 0;

    default:
        break;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

nothrow void createControls(HWND hwnd) {
    hFont = CreateFontW(16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, "Segoe UI"w.ptr);

    hLabel = CreateWindowExW(0, "STATIC"w.ptr, "Enter item name:"w.ptr,
        WS_CHILD | WS_VISIBLE | SS_LEFT, 20, 20, 200, 20, hwnd, cast(HMENU)IDC_LABEL, hInst, null);
    SendMessageW(hLabel, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    hEdit = CreateWindowExW(WS_EX_CLIENTEDGE, "EDIT"w.ptr, ""w.ptr,
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 20, 45, 260, 28, hwnd, cast(HMENU)IDC_MAIN_EDIT, hInst, null);
    SendMessageW(hEdit, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    hBtnAdd = CreateWindowExW(0, "BUTTON"w.ptr, "Add Item"w.ptr,
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON | BS_FLAT, 290, 45, 100, 28, hwnd, cast(HMENU)IDC_BTN_ADD, hInst, null);
    SendMessageW(hBtnAdd, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    hBtnClear = CreateWindowExW(0, "BUTTON"w.ptr, "Clear All"w.ptr,
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON | BS_FLAT, 400, 45, 100, 28, hwnd, cast(HMENU)IDC_BTN_CLEAR, hInst, null);
    SendMessageW(hBtnClear, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    hBtnColor = CreateWindowExW(0, "BUTTON"w.ptr, "Pick Color"w.ptr,
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON | BS_FLAT, 510, 45, 100, 28, hwnd, cast(HMENU)IDC_BTN_COLOR, hInst, null);
    SendMessageW(hBtnColor, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    hList = CreateWindowExW(WS_EX_CLIENTEDGE, "LISTBOX"w.ptr, ""w.ptr,
        WS_CHILD | WS_VISIBLE | WS_VSCROLL | LBS_NOTIFY | LBS_HASSTRINGS, 20, 90, 360, 250, hwnd, cast(HMENU)IDC_LISTBOX, hInst, null);
    SendMessageW(hList, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    hCheck = CreateWindowExW(0, "BUTTON"w.ptr, "Enable extra mode"w.ptr,
        WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 400, 100, 200, 24, hwnd, cast(HMENU)IDC_CHECKBOX, hInst, null);
    SendMessageW(hCheck, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    hRadio1 = CreateWindowExW(0, "BUTTON"w.ptr, "View: Icons"w.ptr,
        WS_CHILD | WS_VISIBLE | BS_AUTORADIOBUTTON | WS_GROUP, 400, 135, 200, 24, hwnd, cast(HMENU)IDC_RADIO1, hInst, null);
    SendMessageW(hRadio1, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    hRadio2 = CreateWindowExW(0, "BUTTON"w.ptr, "View: Details"w.ptr,
        WS_CHILD | WS_VISIBLE | BS_AUTORADIOBUTTON, 400, 165, 200, 24, hwnd, cast(HMENU)IDC_RADIO2, hInst, null);
    SendMessageW(hRadio2, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    auto hSliderLabel = CreateWindowExW(0, "STATIC"w.ptr, "Brightness:"w.ptr,
        WS_CHILD | WS_VISIBLE | SS_LEFT, 400, 205, 200, 20, hwnd, null, hInst, null);
    SendMessageW(hSliderLabel, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    hSlider = CreateWindowExW(0, "msctls_trackbar32"w.ptr, ""w.ptr,
        WS_CHILD | WS_VISIBLE | TBS_AUTOTICKS, 400, 228, 220, 30, hwnd, cast(HMENU)IDC_SLIDER, hInst, null);
    SendMessageW(hSlider, TBM_SETRANGE, TRUE, MAKELONG(0, 100));
    SendMessageW(hSlider, TBM_SETPOS, TRUE, 50);

    auto hProgLabel = CreateWindowExW(0, "STATIC"w.ptr, "Progress:"w.ptr,
        WS_CHILD | WS_VISIBLE | SS_LEFT, 400, 270, 200, 20, hwnd, null, hInst, null);
    SendMessageW(hProgLabel, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    hProgress = CreateWindowExW(0, "msctls_progress32"w.ptr, ""w.ptr,
        WS_CHILD | WS_VISIBLE | PBS_SMOOTH, 400, 293, 220, 22, hwnd, cast(HMENU)IDC_PROGRESS, hInst, null);
    SendMessageW(hProgress, PBM_SETRANGE, 0, MAKELONG(0, 100));
    SendMessageW(hProgress, PBM_SETPOS, 0, 0);

    hStatus = CreateWindowExW(0, "STATIC"w.ptr, "Ready - 0 items"w.ptr,
        WS_CHILD | WS_VISIBLE | SS_LEFT | WS_BORDER, 0, 0, 640, 22, hwnd, cast(HMENU)IDC_STATUS, hInst, null);
    SendMessageW(hStatus, WM_SETFONT, cast(WPARAM)hFont, TRUE);

    SendMessageW(hRadio1, BM_SETCHECK, BST_CHECKED, 0);
}

nothrow void handleAdd(HWND hwnd) {
    wchar[256] wbuf;
    auto len = GetWindowTextW(hEdit, wbuf.ptr, 256);
    if (len == 0) {
        MessageBoxW(hwnd, "Please enter an item name."w.ptr, "Input Required"w.ptr, MB_OK | MB_ICONWARNING);
        return;
    }
    itemCounter++;

    wchar[320] display;
    wchar[16] num;
    intToWStr(itemCounter, num.ptr, 16);
    swprintf(display.ptr, 320, "%ls. %ls"w.ptr, num.ptr, wbuf.ptr);

    SendMessageW(hList, LB_ADDSTRING, 0, cast(LPARAM)display.ptr);
    SetWindowTextW(hEdit, ""w.ptr);
    SetFocus(hEdit);

    int progress = (itemCounter * 10) % 101;
    SendMessageW(hProgress, PBM_SETPOS, progress, 0);

    wchar[300] status;
    swprintf(status.ptr, 300, "Added: \"%ls\" - Total: %d items"w.ptr, wbuf.ptr, itemCounter);
    SetWindowTextW(hStatus, status.ptr);
}

nothrow void handleClear() {
    SendMessageW(hList, LB_RESETCONTENT, 0, 0);
    itemCounter = 0;
    SendMessageW(hProgress, PBM_SETPOS, 0, 0);
    SetWindowTextW(hStatus, "List cleared - 0 items"w.ptr);
}

nothrow void handleColorPick(HWND hwnd) {
    CHOOSECOLORW cc;
    COLORREF[16] custColors;
    cc.lStructSize = CHOOSECOLORW.sizeof;
    cc.hwndOwner = hwnd;
    cc.lpCustColors = custColors.ptr;
    cc.rgbResult = customColor;
    cc.Flags = CC_FULLOPEN | CC_RGBINIT;
    if (ChooseColorW(&cc)) {
        customColor = cc.rgbResult;
        DeleteObject(hBrushBg);
        hBrushBg = CreateSolidBrush(customColor);
        InvalidateRect(hwnd, null, TRUE);
        wchar[80] msg;
        swprintf(msg.ptr, 80, "Background set to RGB(%d, %d, %d)"w.ptr,
            GetRValue(customColor), GetGValue(customColor), GetBValue(customColor));
        SetWindowTextW(hStatus, msg.ptr);
    }
}

nothrow void handleCheckbox() {
    auto checked = SendMessageW(hCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
    SetWindowTextW(hStatus, checked ? "Extra mode: ON"w.ptr : "Extra mode: OFF"w.ptr);
}

nothrow void handleRadio(uint id) {
    SetWindowTextW(hStatus, id == IDC_RADIO1 ? "View: Icons selected"w.ptr : "View: Details selected"w.ptr);
}

nothrow void handleSlider() {
    int pos = cast(int)SendMessageW(hSlider, TBM_GETPOS, 0, 0);
    wchar[40] msg;
    swprintf(msg.ptr, 40, "Brightness: %d%%"w.ptr, pos);
    SetWindowTextW(hStatus, msg.ptr);
}

nothrow void handlePaint(HWND hwnd) {
    PAINTSTRUCT ps;
    HDC hdc = BeginPaint(hwnd, &ps);
    RECT rc;
    GetClientRect(hwnd, &rc);

    HBRUSH hFill = CreateSolidBrush(customColor);
    RECT headerRc = RECT(0, rc.bottom - 50, rc.right, rc.bottom);
    FillRect(hdc, &headerRc, hFill);
    DeleteObject(hFill);

    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, RGB(60, 60, 120));
    HFONT hOldFont = cast(HFONT)SelectObject(hdc, hFont);
    TextOutW(hdc, rc.right - 200, rc.bottom - 35, "D Native Win32 GUI"w.ptr, 18);
    SelectObject(hdc, hOldFont);

    HPEN hPen = CreatePen(PS_SOLID, 2, RGB(180, 180, 200));
    HPEN hOld = cast(HPEN)SelectObject(hdc, hPen);
    MoveToEx(hdc, 20, rc.bottom - 50, null);
    LineTo(hdc, rc.right - 20, rc.bottom - 50);
    SelectObject(hdc, hOld);
    DeleteObject(hPen);

    EndPaint(hwnd, &ps);
}

nothrow void handleResize(HWND hwnd) {
    RECT rc;
    GetClientRect(hwnd, &rc);
    if (hStatus) {
        MoveWindow(hStatus, 0, rc.bottom - 22, rc.right, 22, TRUE);
    }
}

int main() {
    hInst = GetModuleHandleW(null);
    hBrushBg = CreateSolidBrush(customColor);

    WNDCLASSEXW wc;
    wc.cbSize = WNDCLASSEXW.sizeof;
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = &WndProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursorW(null, IDC_ARROW);
    wc.hbrBackground = cast(HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = "DNativeGUI"w.ptr;
    wc.hIcon = LoadIconW(null, IDI_APPLICATION);
    wc.hIconSm = LoadIconW(null, IDI_APPLICATION);

    if (!RegisterClassExW(&wc)) {
        MessageBoxW(null, "Window registration failed."w.ptr, "Error"w.ptr, MB_OK | MB_ICONERROR);
        return 1;
    }

    hMainWnd = CreateWindowExW(
        WS_EX_CONTROLPARENT,
        "DNativeGUI"w.ptr,
        "D Language - Native Windows GUI"w.ptr,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 660, 440,
        null, null, hInst, null
    );

    if (!hMainWnd) {
        MessageBoxW(null, "Window creation failed."w.ptr, "Error"w.ptr, MB_OK | MB_ICONERROR);
        return 1;
    }

    ShowWindow(hMainWnd, SW_SHOW);
    UpdateWindow(hMainWnd);

    SetWindowTextW(hEdit, "Hello from D!"w.ptr);
    SetFocus(hEdit);

    MSG msg;
    while (GetMessageW(&msg, null, 0, 0) > 0) {
        if (!IsDialogMessageW(hMainWnd, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    return cast(int)msg.wParam;
}
