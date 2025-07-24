class ImageActions {
    
    ; Click operations =========================================================================================================================================
    
    static Click(text) {
        return this.New(text).Wait('wait1', -1).Click()    ; waits indefinitely for image to appear then clicks it
    }

    static ClickAllInstances(text) {
        return this.New(text).ClickAllInstances()
    }
    
    static ClickBottomToTop(text) {
        return this.New(text).Wait("wait1", -1).SearchDirection(6).Click()
    }

    static ClickBottomToTopRight(text) {
        return this.New(text).Wait("wait1", -1).SearchDirection(8).Click()
    }

    static ClickInstance(text, instanceNumber) {
        return this.New(text).Wait('wait1', -1).ClickInstance(instanceNumber)
        
    }

    static ClickInstanceLoop(text, instanceNumber) {
        return this.New(text).Wait('wait1', -1).ClickInstanceLoop(instanceNumber)
        
    }

    static ClickInstanceTimeout(text, seconds, instanceNumber) {
        return this.New(text).Timeout(seconds).ClickInstance(instanceNumber)
        
    }

    static ClickMulti(text, timesToClick) {
        return this.New(text).ClickMulti(timesToClick)
    }

    static ClickOffset(text, xOff, yOff) {
        return this.New(text).Wait('wait1', -1).Offset(xOff, yOff).Click()
    }

    static ClickOffsetTimeout(text, xOff, yOff, seconds) {
        return this.New(text).Offset(xOff, yOff).Timeout(seconds).Click()
    }

    static ClickRegion(text, x1, y1, x2, y2) {
        return this.New(text).Wait('wait1', -1).Region(x1, y1, x2, y2).Click()
    }
    
    static ClickRegionOffset(text, x1, y1, x2, y2, xOff, yOff) {
        return this.New(text).Wait('wait1', -1).Region(x1, y1, x2, y2).Offset(xOff, yOff).Click()
    }

    static ClickRegionOffsetSleep(text, x1, y1, x2, y2, xOff, yOff) {
        return this.New(text).Wait('wait1', -1).Region(x1, y1, x2, y2).Offset(xOff, yOff).Sleep(200, 200).Click()
    }

    static ClickRegionTimeout(text, x1, y1, x2, y2, seconds) {
        return this.New(text).Region(x1, y1, x2, y2).Timeout(seconds).Click()
    }
    
    static ClickLeftToRight(text) {
        return this.New(text).Wait('wait1', -1).SearchDirection(5).Click()
    }

    static ClickNoVar(text) {
        return this.New(text).Variation(.00000001).Click()
    }

    static ClickTimeout(text, seconds) {
        return this.New(text).Timeout(seconds).Click()
    }

    static ClickVar(text) {
        return this.New(text).Variation(.1).Click()
    }

    static ClickWebsite(text) {
        return this.New(text).Wait('wait1', -1).Variation(.1).Sleep(400, 300).Click()
    }

    static DoubleClick(text) {
        return this.New(text).Wait('wait1', -1).DoubleClick()
    }

    static DoubleClickOffset(text, xOff, yOff) {
        return this.New(text).Wait('wait1', -1).Offset(xOff, yOff).DoubleClick()
    }

    static DoubleClickRegion(text, x1, y1, x2, y2) {
        return this.New(text).Wait('wait1', -1).Region(x1, y1, x2, y2).DoubleClick()
    }

    static DoubleClickRegionOffset(text, x1, y1, x2, y2, xOff, yOff) {
        return this.New(text).Wait('wait1', -1).Region(x1, y1, x2, y2).Offset(xOff, yOff).DoubleClick()
    }

    static FindAllCoordinates(text) {
        return this.New(text).GetAllCoordinates()
    }

    static FindAllCoordinatesRegion(text, x1, y1, x2, y2) {
        return this.New(text).Region(x1, y1, x2, y2).GetAllCoordinates()
    }

    static Found(text, &X:="", &Y:="") {
        return this.New(text).Find(&X, &Y)
    }
    
    static FoundCenter(text, &X:="", &Y:="") {
        return this.New(text).SearchDirection(9).Find(&X, &Y)
    }
    
    static FoundRegion(text, x1, y1, x2, y2, &X:="", &Y:="") {
        return this.New(text).Region(x1, y1, x2, y2).Find(&X, &Y)
    }

    static FoundTimeout(text, seconds,  &X:="", &Y:="") {
        return this.New(text).Timeout(seconds).Find()
    }

    static FoundVar(text, &X:="", &Y:="") {
        return this.New(text).Wait("wait", .2).Variation(.1).Find(&X, &Y)
    }

    static HighlightInstances(text) {
        return this.New(text).HighlightAllInstances()
    }

    static HighlightInstancesRegion(text, x1, y1, x2, y2) {
        return this.New(text).Region(x1, y1, x2, y2).HighlightAllInstances()
    }

    static Move(text) {
        return this.New(text).Wait("wait1", -1).Move()
    }
    
    static MoveOffset(text, xOff, yOff) {
        return this.New(text).Wait('wait1', -1).Offset(xOff, yOff).Move()
    }

    static MoveRegion(text, x1, y1, x2, y2) {
            return this.New(text).Wait("wait1", -1).Region(x1, y1, x2, y2).Move()
        }
    
    static MoveRegionTimeout(text, x1, y1, x2, y2, seconds) {
        return this.New(text).Region(x1, y1, x2, y2).Timeout(seconds).Move()
    }

    static MoveClickRight(firstImage, secondImage, verticalRange) {
        return this.New(firstImage).MoveClickRight(secondImage, verticalRange)
    }

    static OcrBarDate() {
        return this.New(tws_bar_detail_x).Wait('wait1', -1).Region(5, 879, 41, 919).OcrOffset(tws_bar_detail_text, 4, -4, 69, 12, -1)
    }

    static OcrBarVwap() {
        return this.New(tws_bar_vwap).Wait('wait1', -1).OcrOffset(tws_bar_detail_text, 15, -5, 56, 12, 2)
    }

    static OcrTwsLast(y1, y2, &result:="") {
        return this.New(tws_numbers_active).Region(last_ocr_x1, y1, last_ocr_x2, y2).OCR(&result)
    }

    static OcrIntradayVwap(imageText, ocrText, x1, y1, x2, y2, xOffset, yOffset, width, height, roundResult := -1) {
        return this.New(imageText).Wait('wait1', -1).Region(x1, y1, x2, y2).OcrOffset(ocrText, xOffset, yOffset, width, height, roundResult)
    }

    static RightClick(text) {
        return this.New(text).Wait('wait1', -1).RightClick()
    }

    static RightClickLeftToRight(text) {
        return this.New(text).Wait('wait1', -1).SearchDirection(5).RightClick()
    }

    static RightClickOffset(text, xOff, yOff) {
        return this.New(text).Wait('wait1', -1).Offset(xOff, yOff).RightClick()
    }

    static RightClickRegion(text, x1, y1, x2, y2) {
        return this.New(text).Wait('wait1', -1).Region(x1, y1, x2, y2).RightClick()
    }
    
    static WaitTilFound(text, &X:="", &Y:="") {
        return this.New(text).Wait("wait1", -1).Find(&X, &Y)
    }

    static WaitTilFoundRegion(text, x1, y1, x2, y2, &X:="", &Y:="") {
        return this.New(text).Wait("wait1", -1).Region(x1, y1, x2, y2).Find(&X, &Y)
    }

    static WaitTilFoundVar(text, &X:="", &Y:="") {
        return this.New(text).Wait("wait1", -1).Variation(.1).Find()
    }

    static WaitTilNotFound(text) {
        return this.New(text).Wait("wait0", -1).Find()
    }

    static WaitTilNotFoundRegion(text, x1, y1, x2, y2) {
        return this.New(text).Wait("wait0", -1).Region(x1, y1, x2, y2).Find()
    }

    ;**********************************************************************************************************************************************************************************************************

    class ImageAction {
        __New(text) {
            this.waitType := ""
            this.waitTime := ""
            this.x1 := 0
            this.y1 := 0
            this.x2 := A_ScreenWidth
            this.y2 := A_ScreenHeight
            this.var := 0
            this.text := text
            this.findAll := 0
            this.direction := 1
            this.xOff := 0
            this.yOff := 0
            this.preSleep := 0
            this.postSleep := 0
            this.clickCount := 1
        }

        ; Chainable Configuration Methods ---------------------------------------------------------
   
        Wait(type, time) {
            this.waitType := type
            this.waitTime := time
            return this
        }

        Timeout(seconds) {
            this.waitType := "wait"
            this.waitTime := seconds
            return this
        }
 
        Region(x1, y1, x2, y2) {
            this.x1 := x1
            this.y1 := y1
            this.x2 := x2
            this.y2 := y2
            return this
        }

        Variation(var) {
            this.var := var
            return this
        } 

        SearchDirection(direction) {
            this.direction := direction
            return this
        }
    
        Offset(xOff, yOff) {
            this.xOff := xOff
            this.yOff := yOff
            return this
        }

        Sleep(preSleep, postSleep) {
            this.preSleep := preSleep
            this.postSleep := postSleep
            return this
        }

        ; Core Action Methods ---------------------------------------------------------

        Click() {
            if FindText(&X := this.waitType, &Y := this.waitTime, this.x1, this.y1, this.x2, this.y2, this.var, this.var, this.text,, this.findAll,,,, this.direction,,) {
                Sleep(this.preSleep)
                FindText().Click(X + this.xOff, Y + this.yOff, "L", this.clickCount)
                Sleep(this.postSleep)
                return true
            }
            return false
        }

        ClickAllInstances(minMatches := 0) {
            instances := FindText(&X := this.waitType, &Y := this.waitTime, this.x1, this.y1, this.x2, this.y2, this.var, this.var, this.text,,,,,, this.direction,,)
            if (instances AND instances.Length >= minMatches) {
                for index, result in instances {
                    x := result.x
                    y := result.y
                    FindText().Click(x, y, "L")
                }
                return true
            }
            return false
        }
        
        ClickInstance(instanceNumber) {
                instances := FindText(&X := this.waitType, &Y := this.waitTime, this.x1, this.y1, this.x2, this.y2, this.var, this.var, this.text,,,,,, this.direction,,)
                if (instances AND instances.Length >= instanceNumber) {
                    Instance := instances[instanceNumber]
                    FindText().Click(Instance.x, Instance.y, "L")
                    return true
                }
        }

        ClickInstanceLoop(instanceNumber) {
            loop {
                instances := FindText(&X := this.waitType, &Y := this.waitTime, this.x1, this.y1, this.x2, this.y2, this.var, this.var, this.text,,,,,, this.direction,,)
                if (instances AND instances.Length >= instanceNumber) {
                    Instance := instances[instanceNumber]
                    FindText().Click(Instance.x, Instance.y, "L")
                    return true
                }
            }
        }
        
        ClickMulti(timesToClick) {
            this.clickCount := timesToClick
            return this.Click()
        }

        DoubleClick() {
            this.clickCount := 2
            return this.Click()
        }
    
        Find(&X := "", &Y := "") {
            return FindText(&X := this.waitType, &Y := this.waitTime, this.x1, this.y1, this.x2, this.y2, this.var, this.var, this.text,, this.findAll,,,, this.direction,,)
        }

        GetAllCoordinates() {
            coordinates := []
            instances := FindText(&X := this.waitType, &Y := this.waitTime, this.x1, this.y1, this.x2, this.y2, this.var, this.var, this.text,,,,,, this.direction,,)
            
            if (instances) {
                for index, result in instances {
                    coordinates.Push({ x: result.x, y: result.y })
                }
            }
            
            return coordinates
        }

        HighlightAllInstances(showTime?, color:="Yellow", d:=2) {
            instances := FindText(&X := this.waitType, &Y := this.waitTime, this.x1, this.y1, this.x2, this.y2, this.var, this.var, this.text,,,,,, this.direction,,)
            if (instances) {
                for index, result in instances {
                    Highlight(result.1, result.2, result.3, result.4, showTime?, color, d)
                }
                return true
            }
            return false
        }

        Move() {
            if this.Find(&X, &Y) {
                MouseMove(X + this.xOff, Y + this.yOff)
                return true
            }
            return false
        }

        MoveClickRight(secondImage, verticalRange) {
            if (ok := FindText(&X := "wait1", &Y := -1, this.x1, this.y1, this.x2, this.y2, .1, .1, this.text)) {
                firstX := ok[1].x
                firstY := ok[1].y
                MouseMove(firstX, firstY)
                if (ok2 := FindText(&X := "wait1", &Y := -1, firstX, firstY - verticalRange, A_ScreenWidth, firstY + verticalRange, .1, .1, secondImage)) {
                    Sleep(this.preSleep)
                    FindText().Click(ok2[1].x, ok2[1].y, "L", this.clickCount)
                    Sleep(this.postSleep)
                    return true
                }
            }
            return false
        }
        
        OCR(&result:="") {
            if (ok := FindText(&X := "wait1", &Y := -1, this.x1, this.y1, this.x2, this.y2, this.var, this.var, this.text)) {
                ocrResult := FindText().OCR(ok)
                result := ocrResult.text
                return Number(result)
            }
            return 0
        }

        OcrOffset(ocrText, xOffset, yOffset, width, height, roundResult := -1) {
            if (ok := FindText(&X := this.waitType, &Y := this.waitTime, this.x1, this.y1, this.x2, this.y2, this.var, this.var, this.text)) {
                baseX := ok[1].1
                baseY := ok[1].2
                
                ocrX1 := baseX + xOffset
                ocrY1 := baseY + yOffset
                ocrX2 := ocrX1 + width
                ocrY2 := ocrY1 + height
                
                if (ok2 := FindText(&X := "wait1", &Y := -1, ocrX1, ocrY1, ocrX2, ocrY2, 0, 0, ocrText)) {
                    ocrResult := FindText().OCR(ok2)
                    result := ocrResult.text
                    
                    ; Round the result if specified
                    if (roundResult >= 0 && result != "") {
                        return Round(Number(result), roundResult)
                    }
                    return result
                }
            }
            return ""
        }

        RightClick() {
            if FindText(&X := this.waitType, &Y := this.waitTime, this.x1, this.y1, this.x2, this.y2, this.var, this.var, this.text,, this.findAll,,,, this.direction,,) {
                FindText().Click(X + this.xOff, Y + this.yOff, "R")
                return true
            }
            return false
        }

    }

    static New(text) {
        return ImageActions.ImageAction(text)
    }
}

Highlight(x?, y?, w?, h?, showTime?, color:="Yellow", d:=2) {
	static guis := Map(), timers := Map(), globalClearTimer := ""
	if IsSet(x) {
		if IsObject(x) {
			d := x.HasOwnProp("d") ? x.d : d, color := x.HasOwnProp("color") ? x.color : color, showTime := x.HasOwnProp("showTime") ? x.showTime : showTime
			, h := x.HasOwnProp("h") ? x.h : h, w := x.HasOwnProp("w") ? x.w : h, y := x.HasOwnProp("y") ? x.y : y, x := x.HasOwnProp("x") ? x.x : unset
		}
		if !(IsSet(x) && IsSet(y) && IsSet(w) && IsSet(h))
			throw ValueError("x, y, w and h arguments must all be provided for a highlight", -1)
		for k, v in guis {
			if k.x = x && k.y = y && k.w = w && k.h = h {
				if !IsSet(showTime) || (IsSet(showTime) && showTime = "clear")
					TryRemoveTimer(k), TryDeleteGui(k)
				else if showTime = 0
					TryRemoveTimer(k)
				else if IsInteger(showTime) {
					if showTime < 0 {
						if !timers.Has(k)
							timers[k] := Highlight.Bind(x,y,w,h)
						SetTimer(timers[k], showTime)
					} else {
						TryRemoveTimer(k)
					}
				} else
					throw ValueError('Invalid showTime value "' (!IsSet(showTime) ? "unset" : IsObject(showTime) ? "{Object}" : showTime) '"', -1)
				return
			}
		}
	} else {
		if globalClearTimer
			SetTimer(globalClearTimer, 0), globalClearTimer := ""
		for k, v in timers
			SetTimer(v, 0)
		for k, v in guis
			v.Destroy()
		guis := Map(), timers := Map()
		return
	}
	
	if (showTime := showTime ?? 3000) = "clear"
		return
	else if !IsInteger(showTime)
		throw ValueError('Invalid showTime value "' (!IsSet(showTime) ? "unset" : IsObject(showTime) ? "{Object}" : showTime) '"', -1)

	loc := {x:x, y:y, w:w, h:h}
	guis[loc] := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
	GuiObj := guis[loc]
	GuiObj.BackColor := color
	iw:= w+d, ih:= h+d, w:=w+d*2, h:=h+d*2, x:=x-d, y:=y-d
	WinSetRegion("0-0 " w "-0 " w "-" h " 0-" h " 0-0 " d "-" d " " iw "-" d " " iw "-" ih " " d "-" ih " " d "-" d, GuiObj.Hwnd)
	GuiObj.Show("NA x" . x . " y" . y . " w" . w . " h" . h)

	if showTime > 0 {
		if guis.Count = 1 {
			globalClearTimer := ClearAllHighlights
			SetTimer(globalClearTimer, showTime)
		}
	} else if showTime < 0 {
		if guis.Count = 1 {
			globalClearTimer := ClearAllHighlights
			SetTimer(globalClearTimer, -showTime)
		}
	}

    ClearAllHighlights() {
        if globalClearTimer
            SetTimer(globalClearTimer, 0), globalClearTimer := ""
        for k, v in timers
            SetTimer(v, 0)
        for k, v in guis
            v.Destroy()
        guis := Map(), timers := Map()
    }

    TryRemoveTimer(key) {
        if timers.Has(key)
            SetTimer(timers[key], 0), timers.Delete(key)
    }

    TryDeleteGui(key) {
        if guis.Has(key)
            guis[key].Destroy(), guis.Delete(key)
    }
}
