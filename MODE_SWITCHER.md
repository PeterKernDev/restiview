# MODE_SWITCHER.md
# Test Mode vs Real Mode Configuration

## Quick Mode Switch

### For TESTING (using yesterday's already-fetched data):
**File:** `VER5_AI_Update_Daily_History.py`  
**Line 31:** `TEST_MODE = True`

### For REAL OPERATION (fetch fresh data from yfinance):
**File:** `VER5_AI_Update_Daily_History.py`  
**Line 31:** `TEST_MODE = False`

---

## How Each Mode Works

### TEST MODE (`TEST_MODE = True`)
- ✓ **Fast** - No API calls, uses existing CSV
- ✓ **Safe** - Won't use API quota
- ✓ **Repeatable** - Same data every time
- Uses: `C:\AI Data\Data Output\History\SHistory_2026-01-29.csv`
- Perfect for: Development, testing, debugging

### REAL MODE (`TEST_MODE = False`)
- ✓ **Live Data** - Fetches from yfinance API
- ✓ **Current** - Gets actual yesterday's market data
- ✓ **Production** - Daily automated operation
- ⚠ **Slow** - Takes 30-60 minutes for all tickers
- ⚠ **API Calls** - Uses network and yfinance quota

---

## Quick Testing Commands

### Test with existing data (fast):
```powershell
# Make sure TEST_MODE = True in VER5_AI_Update_Daily_History.py
python RUN_SIMPLE_TEST.py
```

### Run real daily update (slow):
```powershell
# Change TEST_MODE = False in VER5_AI_Update_Daily_History.py
python VER5_AI_Update_Daily_History.py
```

### Complete workflow with master control:
```powershell
python VER5_AI_Master_Control.py
```

---

## File Locations

### Configuration Files:
- **Update Script**: `c:\dev\RestiView2\restiview\VER5_AI_Update_Daily_History.py`
  - Line 31: `TEST_MODE = True/False`
  - Line 32: `TEST_DATA_FILE = ...` (which test file to use)

### Test Data:
- **Yesterday's Data**: `C:\AI Data\Data Output\History\SHistory_2026-01-29.csv`
- **Long Format DB**: `C:\AI Data\Data Output\History\SHistory_LongFormat.parquet`

### Output:
- **Excel Reports**: `C:\AI Data\Data Output\History\Golden_Cross_Report_*.xlsx`
- **Logs**: `C:\AI Data\Data Output\History\update_log.txt`

---

## Typical Workflow

### Initial Setup (One Time):
1. Set `TEST_MODE = True`
2. Run `python VER5_AI_Migrate_To_LongFormat.py` (converts old batch files)
3. Run `python RUN_SIMPLE_TEST.py` (tests everything)

### Daily Testing (During Development):
1. Keep `TEST_MODE = True`
2. Run `python RUN_SIMPLE_TEST.py`
3. Check Excel report
4. Repeat as needed (very fast)

### Production Deployment:
1. Change `TEST_MODE = False`
2. Set up Windows Task Scheduler to run `VER5_AI_Master_Control.py` daily
3. Schedule for after market close (e.g., 7:00 PM ET)

---

## Switching Between Modes

Edit `VER5_AI_Update_Daily_History.py` around line 31:

```python
# For testing:
TEST_MODE = True  # ← Uses existing CSV data (fast)

# For production:
TEST_MODE = False  # ← Fetches from yfinance (slow, live data)
```

**No other changes needed!** The code automatically adapts based on this flag.
