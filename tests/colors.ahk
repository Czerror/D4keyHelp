for col, expected in [0x841807, 0x73AE0E, 0x14218C, 0x292A28] {
    panel := Gui("+ToolWindow -Caption +AlwaysOnTop")
    try {
        panel.BackColor := Format("{:06X}", expected)
        panel.Show("NA x80 y80 w96 h96")
        WinRedraw(panel.Hwnd)
        WinGetClientPos(&x, &y,,, panel.Hwnd)
        CoordMode "Pixel", "Screen"
        old := PixelGetColor(x+40, y+40, "RGB")
        rgb := ColorDetector.GetPixelRGB(x+40, y+40)
        Assert(old = rgb, "v2 explicit RGB and default sample match")
        Assert(rgb = expected, "controlled color not visible at the sampled pixel")
        for index, name in ["IsRed", "IsGreen", "IsBlue", "IsGray"]
            Assert(ColorDetector.%name%(rgb) == (col == index), name " on sample " col)
    } finally {
        panel.Destroy()
    }
}
