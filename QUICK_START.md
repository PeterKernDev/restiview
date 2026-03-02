# QUICK START GUIDE - Stock Analysis System

## What You Have Now

✅ **Complete automated stock analysis system** with:
- Historical data management (rolling 4-year window)
- Daily automated updates
- Golden cross detection
- Professional Excel reports

## Two Operating Modes

### 🧪 TEST MODE (Current Setting)
**Use for:** Development, testing, debugging  
**Speed:** ⚡ Very fast (seconds to minutes)  
**Data source:** Yesterday's pre-fetched CSV file  
**Setting:** `TEST_MODE = True` in VER5_AI_Update_Daily_History.py

### 🚀 REAL MODE  
**Use for:** Production, daily automation  
**Speed:** 🐢 Slow (30-60 minutes)  
**Data source:** Live yfinance API  
**Setting:** `TEST_MODE = False` in VER5_AI_Update_Daily_History.py

---

## 🎯 Quick Test (Using Yesterday's Data)

```powershell
cd c:\dev\RestiView2\restiview
py RUN_SIMPLE_TEST.py
```

This will:
1. ✓ Migrate your old batch files (first time only)
2. ✓ Add yesterday's data to the database
3. ✓ Generate golden cross Excel report

**Time:** 2-5 minutes (first run), <1 minute (subsequent runs)

---

## 📊 What Gets Created

### Data Files (in `C:\AI Data\Data Output\History\`)
- `SHistory_LongFormat.parquet` - Main database (efficient binary format)
- `SHistory_LongFormat.csv` - Backup (human-readable)
- `Golden_Cross_Report_YYYY-MM-DD.xlsx` - Analysis with charts

### Structure
```
Long Format Database:
┌────────┬────────────┬────────┬──────────┐
│ Ticker │ Date       │ Close  │ Volume   │
├────────┼────────────┼────────┼──────────┤
│ AAPL   │ 2022-04-01 │ 174.31 │ 89116800 │
│ AAPL   │ 2022-04-04 │ 178.44 │ 82982400 │
│ MSFT   │ 2022-04-01 │ 310.22 │ 28453100 │
│ ...    │ ...        │ ...    │ ...      │
└────────┴────────────┴────────┴──────────┘
~8,780 tickers × ~950 trading days = ~8.3 million records
```

---

## 🔄 Switching to Real Mode (Production)

When ready for daily automation:

1. **Edit:** `VER5_AI_Update_Daily_History.py` (line 31)
   ```python
   TEST_MODE = False  # ← Change True to False
   ```

2. **Run manually once to test:**
   ```powershell
   py VER5_AI_Update_Daily_History.py
   ```
   (This will take 30-60 minutes)

3. **Set up automation** (Windows Task Scheduler):
   - See [STOCK_SYSTEM_README.md](STOCK_SYSTEM_README.md) for full instructions
   - Run daily at 7:00 PM (after market close)
   - Executes: `VER5_AI_Master_Control.py`

---

## 📁 File Guide

### Main Programs
| File | Purpose | When to Run |
|------|---------|-------------|
| `VER5_AI_Migrate_To_LongFormat.py` | Convert old batch files | **Once** (first setup) |
| `VER5_AI_Update_Daily_History.py` | Add new data | **Daily** (automated) |
| `VER5_AI_Golden_Cross_Predictor.py` | Generate Excel report | **Daily** (automated) |
| `VER5_AI_Master_Control.py` | Run update + predictor | **Daily** (orchestrator) |

### Helper Scripts
| File | Purpose |
|------|---------|
| `RUN_SIMPLE_TEST.py` | Quick test of full workflow |
| `RUN_TEST_WORKFLOW.py` | Detailed test with logging |
| `VER5_AI_S0_V3_History.py` | Original data fetcher (standalone) |

### Documentation
| File | Contents |
|------|----------|
| `STOCK_SYSTEM_README.md` | Complete system documentation |
| `MODE_SWITCHER.md` | Test vs Real mode guide |
| `QUICK_START.md` | This file |

---

## 🎓 Understanding Golden Crosses

**What is it?**  
A bullish technical indicator that occurs when the 50-day moving average crosses above the 200-day moving average.

**Excel Report Contains:**
- 📊 **Summary Sheet:** Top 20 recent crosses with key metrics
- 📈 **Individual Sheets:** Charts for each ticker showing the cross
- 🎯 **Recent Crosses Only:** Configurable lookback (default: 5 days)

**How to Use:**
1. Open the Excel report
2. Review Summary sheet for crosses in last 5 days
3. Click individual ticker sheets for visual confirmation
4. Use as screening tool (not standalone trading signal)

---

## 🔧 Customization Options

### Change Analysis Parameters
Edit `VER5_AI_Golden_Cross_Predictor.py`:
```python
SHORT_MA = 50      # Short-term moving average days
LONG_MA = 200      # Long-term moving average days
LOOKBACK_DAYS = 5  # Show crosses within last N days
```

### Change Data Retention
Edit `VER5_AI_Update_Daily_History.py`:
```python
TARGET_DAYS = 950  # Number of trading days to keep
```

### Use Different Test Data
Edit `VER5_AI_Update_Daily_History.py`:
```python
TEST_DATA_FILE = DATA_DIR / "SHistory_2026-01-29.csv"  # Your test file
```

---

## ❓ Troubleshooting

### "No historical data found"
→ Run migration first: `py VER5_AI_Migrate_To_LongFormat.py`

### "Test data file not found"
→ Make sure `SHistory_2026-01-29.csv` exists in `C:\AI Data\Data Output\History\`

### "No golden crosses found"
→ Normal! Market conditions vary. Try increasing `LOOKBACK_DAYS` or check different dates

### Excel file won't open
→ Make sure openpyxl is installed: `pip install openpyxl`

---

## 📞 Next Steps

### For Testing (Now)
1. ✅ Run `py RUN_SIMPLE_TEST.py`
2. ✅ Check the Excel report
3. ✅ Verify data looks correct
4. ✅ Repeat tests as needed (very fast with TEST_MODE)

### For Production (When Ready)
1. Switch to `TEST_MODE = False`
2. Test one real data fetch manually
3. Set up Task Scheduler for daily automation
4. Monitor logs for first week

### For Customization
1. Adjust moving average periods as desired
2. Change lookback window for crosses
3. Add additional technical indicators
4. Export to different formats

---

**Last Updated:** 2026-01-30  
**Current Mode:** TEST (using yesterday's pre-fetched data)  
**Ready for:** Testing and validation
