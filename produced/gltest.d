import core.sys.windows.windows;
import core.sys.windows.wingdi;

extern(System) nothrow @nogc {
    void glClearColor(float, float, float, float);
    void glClear(uint);
    void glViewport(int, int, int, int);
    void glEnable(uint);
    void glDisable(uint);
    void glBegin(uint);
    void glEnd();
    void glVertex2f(float, float);
    void glColor4f(float, float, float, float);
    void glMatrixMode(uint);
    void glLoadIdentity();
    void glOrtho(double, double, double, double, double, double);
    void glFlush();
    void glBlendFunc(uint, uint);
    void glRectf(float, float, float, float);
}

enum GL_COLOR_BUFFER_BIT = 0x4000;
enum GL_BLEND = 0x0BE2;
enum GL_SRC_ALPHA = 0x0302;
enum GL_ONE_MINUS_SRC_ALPHA = 0x0303;
enum GL_PROJECTION = 0x1701;
enum GL_MODELVIEW = 0x1700;
enum GL_QUADS = 0x0007;
enum GL_TRIANGLES = 0x0004;

__gshared HWND g_hwnd;
__gshared HDC g_hdc;
__gshared HGLRC g_hglrc;
__gshared bool g_close;

extern(Windows) LRESULT WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) nothrow {
    if (msg == 0x0010) { g_close = true; return 0; } /* WM_CLOSE */
    if (msg == 0x0002) { PostQuitMessage(0); return 0; } /* WM_DESTROY */
    return DefWindowProcW(hwnd, msg, wp, lp);
}

int main() {
    auto hInst = GetModuleHandleW(null);

    WNDCLASSEXW wc;
    wc.cbSize = wc.sizeof;
    wc.style = 3; /* CS_HREDRAW | CS_VREDRAW */
    wc.lpfnWndProc = &WndProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursorW(null, cast(wchar*)32512); /* IDC_ARROW */
    wc.lpszClassName = "GLTest"w.ptr;
    RegisterClassExW(&wc);

    RECT rc = RECT(0, 0, 800, 600);
    AdjustWindowRectEx(&rc, 0x00CF0000, 0, 0); /* WS_OVERLAPPEDWINDOW */

    g_hwnd = CreateWindowExW(0, "GLTest"w.ptr, "GL Test"w.ptr,
        0x00CF0000 | 0x10000000, /* WS_OVERLAPPEDWINDOW | WS_VISIBLE */
        0x80000000, 0x80000000, rc.right - rc.left, rc.bottom - rc.top,
        null, null, hInst, null);

    if (!g_hwnd) { MessageBoxW(null, "No window"w.ptr, "Err"w.ptr, 0); return 1; }

    g_hdc = GetDC(g_hwnd);

    PIXELFORMATDESCRIPTOR pfd;
    pfd.nSize = cast(ushort)pfd.sizeof;
    pfd.nVersion = 1;
    pfd.dwFlags = 0x00000004 | 0x00000001 | 0x00000002; /* PFD_DRAW_TO_WINDOW | SUPPORT_OPENGL | DOUBLEBUFFER */
    pfd.iPixelType = 0;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 16;
    pfd.iLayerType = 0;
    int pf = ChoosePixelFormat(g_hdc, &pfd);
    SetPixelFormat(g_hdc, pf, &pfd);

    g_hglrc = wglCreateContext(g_hdc);
    if (!g_hglrc) { MessageBoxW(null, "No GL context"w.ptr, "Err"w.ptr, 0); return 1; }
    wglMakeCurrent(g_hdc, g_hglrc);

    /* setup 2D projection */
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, 800, 600, 0, -1, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    g_close = false;
    int frame = 0;

    while (!g_close) {
        MSG msg;
        while (PeekMessageW(&msg, null, 0, 0, 1)) { /* PM_REMOVE */
            if (msg.message == 0x0012) { g_close = true; break; } /* WM_QUIT */
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        if (g_close) break;

        glClearColor(0.2f, 0.3f, 0.4f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        /* draw a white rectangle */
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
        glBegin(GL_QUADS);
        glVertex2f(100, 100);
        glVertex2f(300, 100);
        glVertex2f(300, 200);
        glVertex2f(100, 200);
        glEnd();

        /* draw a red rectangle */
        glColor4f(1.0f, 0.2f, 0.2f, 1.0f);
        glRectf(350, 100, 550, 200);

        glFlush();
        SwapBuffers(g_hdc);
        frame++;
    }

    wglMakeCurrent(null, null);
    wglDeleteContext(g_hglrc);
    ReleaseDC(g_hwnd, g_hdc);
    DestroyWindow(g_hwnd);
    return 0;
}
