; Return fixed RGB values at known coordinates, without reading the user's display.
PixelGetColor(x, y, mode := "") {
    static samples := [0x841807, 0x73AE0E, 0x14218C, 0x292A28]
    Assert(y == 1 && mode == "", "sample uses the default v2 method at the requested row")
    return Format("0x{:06X}", samples[x])
}

for col, expected in [0x841807, 0x73AE0E, 0x14218C, 0x292A28] {
    rgb := ColorDetector.GetPixelRGB(col, 1)
    Assert(rgb = expected, "RGB channels are retained")
    for index, name in ["IsRed", "IsGreen", "IsBlue", "IsGray"]
        Assert(ColorDetector.%name%(rgb) == (col == index), name " on sample " col)
}
