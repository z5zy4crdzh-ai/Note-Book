## Android 原生Car快速设置下拉框bug修复

最近修复了一个原生安卓的bug，感觉很好玩，分享一下，虽然改动不多，但是解决思路和代码分析可以记录下来。

bug现象：

1.移动网络按钮点击功能没有问题，不会受到其他三个按钮影响，单独控制

2.移动网络按钮图标单击无变化，但是功能已启用，再点击其他三个按钮，移动网络图标则正确变化

3.移动网络按钮图标单击无变化，但是功能已启用，退出下拉框再进入，图标变化则成功刷新

目前来看就是，问题出在移动网络的按钮图标点击是没有立即刷新的，然后其他三个图标点击就会让他刷新，重新打开下拉框也会刷新，就是点击他自己不会刷新。

后面去看了谷歌源码，发现这部分代码已经给重构了，刚开始让我感觉这个bug难度很大。

![image-20240408152856699]()

![image.png](https://p1-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/64515684b99140f695511a02ceef6b82~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=1130&h=688&s=153807&e=png&b=fefefe)

1.一开始我是想到是不是xml文件的问题，经过查看发现关于数据网络图标只有一个xml文件，矢量绘制的，然后我随机把数据网络图标替换成其他三个图标中的一个，发现不会立即刷新，即使刷新了也是替换图标变暗了，排除xml文件图标错误

```
public Drawable getIcon() {
        return mContext.getDrawable(R.drawable.ic_cellular_data);
    }
```

2.然后我就思考为什么其他按钮会影响到他的刷新，自己的点击事件不会刷新，所以去看了其他三个图标按钮代码

这里是数据网络按钮的源码

packages\apps\Car\Settings\src\com\android\car\settings\quicksettings

```
/**
 * Controls cellular on quick setting page.
 */
public class CelluarTile implements QuickSettingGridAdapter.Tile, DataUsageController.Callback {
    private final Context mContext;
    private final StateChangedListener mStateChangedListener;
    private final DataUsageController mDataUsageController;
    @Nullable
    private final String mCarrierName;
    private final boolean mAvailable;
    private final View.OnLongClickListener mLaunchDisplaySettings;

    private State mState = State.ON;

    CelluarTile(Context context, StateChangedListener stateChangedListener,
            FragmentHost fragmentHost) {
        mStateChangedListener = stateChangedListener;
        mContext = context;
        TelephonyManager manager =
                (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
        mDataUsageController = new DataUsageController(mContext);
        mDataUsageController.setCallback(this);
        mAvailable = mDataUsageController.isMobileDataSupported();
        mState = mAvailable && mDataUsageController.isMobileDataEnabled() ? State.ON : State.OFF;
        mCarrierName = mAvailable ? manager.getNetworkOperatorName() : null;

        mLaunchDisplaySettings = v -> {
            context.startActivity(new Intent(context,
                    CarSettingActivities.MobileNetworkActivity.class));
            return true;
        };
    }

    @Override
    public void onMobileDataEnabled(boolean enabled) {
        mState = enabled ? State.ON : State.OFF;
    }

    @Override
    public View.OnLongClickListener getOnLongClickListener() {
        return mLaunchDisplaySettings;
    }

    @Override
    public boolean isAvailable() {
        return mAvailable;
    }

    @Override
    public Drawable getIcon() {
        return mContext.getDrawable(R.drawable.ic_cellular_data);
    }

    @Override
    @Nullable
    public String getText() {
        return mCarrierName;
    }

    @Override
    public State getState() {
        return mState;
    }

    @Override
    public void start() {
    }

    @Override
    public void stop() {
    }

    @Override
    public void onClick(View v) {
        mDataUsageController.setMobileDataEnabled(!mDataUsageController.isMobileDataEnabled());
    }
}

```

这是夜间模式按钮代码：

```
/**
 * Toggles auto or night mode tile on quick setting page.
 */
public class DayNightTile implements QuickSettingGridAdapter.Tile {
    private final Context mContext;
    private final StateChangedListener mStateChangedListener;
    private final UiModeManager mUiModeManager;
    private final View.OnLongClickListener mLaunchDisplaySettings;

    @DrawableRes
    private int mIconRes = R.drawable.ic_settings_night_display;

    private final String mText;

    private State mState = State.ON;

    DayNightTile(
            Context context,
            StateChangedListener stateChangedListener,
            FragmentHost fragmentHost) {
        mStateChangedListener = stateChangedListener;
        mContext = context;
        mUiModeManager = (UiModeManager) mContext.getSystemService(Context.UI_MODE_SERVICE);
        if (mUiModeManager.getNightMode() == UiModeManager.MODE_NIGHT_YES) {
            mState = State.ON;
        } else {
            mState = State.OFF;
        }
        mText = mContext.getString(R.string.night_mode_tile_label);
        mLaunchDisplaySettings = v -> {
            context.startActivity(new Intent(context,
                    CarSettingActivities.DisplaySettingsActivity.class));
            return true;
        };
    }

    @Nullable
    public View.OnLongClickListener getOnLongClickListener() {
        return mLaunchDisplaySettings;
    }

    @Override
    public boolean isAvailable() {
        return true;
    }

    @Override
    public Drawable getIcon() {
        return mContext.getDrawable(mIconRes);
    }

    @Override
    @Nullable
    public String getText() {
        return mText;
    }

    @Override
    public State getState() {
        return mState;
    }

    @Override
    public void start() {
    }

    @Override
    public void stop() {
    }

    @Override
    public void onClick(View v) {
        if (mUiModeManager.getNightMode() == UiModeManager.MODE_NIGHT_YES) {
            mUiModeManager.setNightMode(UiModeManager.MODE_NIGHT_NO);
        } else {
            mUiModeManager.setNightMode(UiModeManager.MODE_NIGHT_YES);
        }
    }
}
```

看到这里发现大体的逻辑是基本差不多的，有差异的地方是，夜间模式的获取图标资源文件是没有写死的

```
private int mIconRes = R.drawable.ic_settings_night_display;
public Drawable getIcon() {
        return mContext.getDrawable(mIconRes);
    }
```

还有具体的功能实现逻辑不同，基本上也是判断是否启用和切换模式，因为数据网络功能是正常的，所以这里稍微是看了一下mDataUsageController这部分的代码，看看有没有收获，其实数据网络这里有一个回调函数，mDataUsageController.setCallback(this);，其他按钮逻辑并没有回调函数，当时并没有注意到。

```
// 这是数据网络的功能实现逻辑的方法
private final DataUsageController mDataUsageController;
mDataUsageController = new DataUsageController(mContext);
mDataUsageController.setCallback(this);
mAvailable = mDataUsageController.isMobileDataSupported();
mState = mAvailable && mDataUsageController.isMobileDataEnabled() ? State.ON : State.OFF;

// 这是夜间模式图标的实现逻辑的方法
private final UiModeManager mUiModeManager;
if (mUiModeManager.getNightMode() == UiModeManager.MODE_NIGHT_YES) {
            mUiModeManager.setNightMode(UiModeManager.MODE_NIGHT_NO);
        } else {
            mUiModeManager.setNightMode(UiModeManager.MODE_NIGHT_YES);
        }
```

接下里就看DataUsageController这部分代码，这个类在很多地方用了，大概率是不会在这里出错误的，这里看看他的逻辑

frameworks\base\packages\SettingsLib\src\com\android\settingslib\net\DataUsageController.java

```
public class DataUsageController {

    private static final String TAG = "DataUsageController";
    private static final boolean DEBUG = Log.isLoggable(TAG, Log.DEBUG);
    private static final int FIELDS = FIELD_RX_BYTES | FIELD_TX_BYTES;
    private static final StringBuilder PERIOD_BUILDER = new StringBuilder(50);
    private static final java.util.Formatter PERIOD_FORMATTER = new java.util.Formatter(
            PERIOD_BUILDER, Locale.getDefault());

    private final Context mContext;
    private final ConnectivityManager mConnectivityManager;
    private final INetworkStatsService mStatsService;
    private final NetworkPolicyManager mPolicyManager;
    private final NetworkStatsManager mNetworkStatsManager;

    private INetworkStatsSession mSession;
    private Callback mCallback;
    private NetworkNameProvider mNetworkController;
    private int mSubscriptionId;

    public DataUsageController(Context context) {
        mContext = context;
        mConnectivityManager = ConnectivityManager.from(context);
        mStatsService = INetworkStatsService.Stub.asInterface(
                ServiceManager.getService(Context.NETWORK_STATS_SERVICE));
        mPolicyManager = NetworkPolicyManager.from(mContext);
        mNetworkStatsManager = context.getSystemService(NetworkStatsManager.class);
        mSubscriptionId = SubscriptionManager.INVALID_SUBSCRIPTION_ID;
    }

    public void setNetworkController(NetworkNameProvider networkController) {
        mNetworkController = networkController;
    }

    /**
     * By default this class will just get data usage information for the default data subscription,
     * but this method can be called to require it to use an explicit subscription id which may be
     * different from the default one (this is useful for the case of multi-SIM devices).
     */
    public void setSubscriptionId(int subscriptionId) {
        mSubscriptionId = subscriptionId;
    }

    /**
     * Returns the default warning level in bytes.
     */
    public long getDefaultWarningLevel() {
        return MB_IN_BYTES
                * mContext.getResources().getInteger(R.integer.default_data_warning_level_mb);
    }

    public void setCallback(Callback callback) {
        mCallback = callback;
    }

    private DataUsageInfo warn(String msg) {
        Log.w(TAG, "Failed to get data usage, " + msg);
        return null;
    }

    public DataUsageInfo getDataUsageInfo() {
        NetworkTemplate template = DataUsageUtils.getMobileTemplate(mContext, mSubscriptionId);

        return getDataUsageInfo(template);
    }

    public DataUsageInfo getWifiDataUsageInfo() {
        NetworkTemplate template = NetworkTemplate.buildTemplateWifiWildcard();
        return getDataUsageInfo(template);
    }

    public DataUsageInfo getDataUsageInfo(NetworkTemplate template) {
        final NetworkPolicy policy = findNetworkPolicy(template);
        final long now = System.currentTimeMillis();
        final long start, end;
        final Iterator<Range<ZonedDateTime>> it = (policy != null) ? policy.cycleIterator() : null;
        if (it != null && it.hasNext()) {
            final Range<ZonedDateTime> cycle = it.next();
            start = cycle.getLower().toInstant().toEpochMilli();
            end = cycle.getUpper().toInstant().toEpochMilli();
        } else {
            // period = last 4 wks
            end = now;
            start = now - DateUtils.WEEK_IN_MILLIS * 4;
        }
        final long totalBytes = getUsageLevel(template, start, end);
        if (totalBytes < 0L) {
            return warn("no entry data");
        }
        final DataUsageInfo usage = new DataUsageInfo();
        usage.startDate = start;
        usage.usageLevel = totalBytes;
        usage.period = formatDateRange(start, end);
        usage.cycleStart = start;
        usage.cycleEnd = end;

        if (policy != null) {
            usage.limitLevel = policy.limitBytes > 0 ? policy.limitBytes : 0;
            usage.warningLevel = policy.warningBytes > 0 ? policy.warningBytes : 0;
        } else {
            usage.warningLevel = getDefaultWarningLevel();
        }
        if (usage != null && mNetworkController != null) {
            usage.carrier = mNetworkController.getMobileDataNetworkName();
        }
        return usage;
    }

    /**
     * Get the total usage level recorded in the network history
     * @param template the network template to retrieve the network history
     * @return the total usage level recorded in the network history or -1L if there is error
     * retrieving the data.
     */
    public long getHistoricalUsageLevel(NetworkTemplate template) {
        return getUsageLevel(template, 0L /* start */, System.currentTimeMillis() /* end */);
    }

    private long getUsageLevel(NetworkTemplate template, long start, long end) {
        try {
            final Bucket bucket = mNetworkStatsManager.querySummaryForDevice(template, start, end);
            if (bucket != null) {
                return bucket.getRxBytes() + bucket.getTxBytes();
            }
            Log.w(TAG, "Failed to get data usage, no entry data");
        } catch (RemoteException e) {
            Log.w(TAG, "Failed to get data usage, remote call failed");
        }
        return -1L;
    }

    private NetworkPolicy findNetworkPolicy(NetworkTemplate template) {
        if (mPolicyManager == null || template == null) return null;
        final NetworkPolicy[] policies = mPolicyManager.getNetworkPolicies();
        if (policies == null) return null;
        final int N = policies.length;
        for (int i = 0; i < N; i++) {
            final NetworkPolicy policy = policies[i];
            if (policy != null && template.equals(policy.template)) {
                return policy;
            }
        }
        return null;
    }

    private static String statsBucketToString(Bucket bucket) {
        return bucket == null ? null : new StringBuilder("Entry[")
            .append("bucketDuration=").append(bucket.getEndTimeStamp() - bucket.getStartTimeStamp())
            .append(",bucketStart=").append(bucket.getStartTimeStamp())
            .append(",rxBytes=").append(bucket.getRxBytes())
            .append(",rxPackets=").append(bucket.getRxPackets())
            .append(",txBytes=").append(bucket.getTxBytes())
            .append(",txPackets=").append(bucket.getTxPackets())
            .append(']').toString();
    }

    @VisibleForTesting
    public TelephonyManager getTelephonyManager() {
        int subscriptionId = mSubscriptionId;

        // If mSubscriptionId is invalid, get default data sub.
        if (!SubscriptionManager.isValidSubscriptionId(subscriptionId)) {
            subscriptionId = SubscriptionManager.getDefaultDataSubscriptionId();
        }

        // If data sub is also invalid, get any active sub.
        if (!SubscriptionManager.isValidSubscriptionId(subscriptionId)) {
            int[] activeSubIds = SubscriptionManager.from(mContext).getActiveSubscriptionIdList();
            if (!ArrayUtils.isEmpty(activeSubIds)) {
                subscriptionId = activeSubIds[0];
            }
        }

        return mContext.getSystemService(
                TelephonyManager.class).createForSubscriptionId(subscriptionId);
    }

    public void setMobileDataEnabled(boolean enabled) {
        Log.d(TAG, "setMobileDataEnabled: enabled=" + enabled);
        getTelephonyManager().setDataEnabled(enabled);
        if (mCallback != null) {
            mCallback.onMobileDataEnabled(enabled);
        }
    }

    public boolean isMobileDataSupported() {
        // require both supported network and ready SIM
        return mConnectivityManager.isNetworkSupported(TYPE_MOBILE)
                && getTelephonyManager().getSimState() == SIM_STATE_READY;
    }

    public boolean isMobileDataEnabled() {
        return getTelephonyManager().isDataEnabled();
    }

    static int getNetworkType(NetworkTemplate networkTemplate) {
        if (networkTemplate == null) {
            return ConnectivityManager.TYPE_NONE;
        }
        final int matchRule = networkTemplate.getMatchRule();
        switch (matchRule) {
            case NetworkTemplate.MATCH_MOBILE:
            case NetworkTemplate.MATCH_MOBILE_WILDCARD:
                return ConnectivityManager.TYPE_MOBILE;
            case NetworkTemplate.MATCH_WIFI:
            case NetworkTemplate.MATCH_WIFI_WILDCARD:
                return  ConnectivityManager.TYPE_WIFI;
            case NetworkTemplate.MATCH_ETHERNET:
                return  ConnectivityManager.TYPE_ETHERNET;
            default:
                return ConnectivityManager.TYPE_MOBILE;
        }
    }

    private String getActiveSubscriberId() {
        final String actualSubscriberId = getTelephonyManager().getSubscriberId();
        return actualSubscriberId;
    }

    private String formatDateRange(long start, long end) {
        final int flags = FORMAT_SHOW_DATE | FORMAT_ABBREV_MONTH;
        synchronized (PERIOD_BUILDER) {
            PERIOD_BUILDER.setLength(0);
            return DateUtils.formatDateRange(mContext, PERIOD_FORMATTER, start, end, flags, null)
                    .toString();
        }
    }

    public interface NetworkNameProvider {
        String getMobileDataNetworkName();
    }

    public static class DataUsageInfo {
        public String carrier;
        public String period;
        public long startDate;
        public long limitLevel;
        public long warningLevel;
        public long usageLevel;
        public long cycleStart;
        public long cycleEnd;
    }

    public interface Callback {
        void onMobileDataEnabled(boolean enabled);
    }
}
```

里面最关键的就是这个方法，setMobileDataEnabled这里回调了onMobileDataEnabled(enabled)这个函数

```
public void setMobileDataEnabled(boolean enabled) {
        Log.d(TAG, "setMobileDataEnabled: enabled=" + enabled);
        getTelephonyManager().setDataEnabled(enabled);
        if (mCallback != null) {
            mCallback.onMobileDataEnabled(enabled);
        }
    }
```

回到数据网络图标代码的onMobileDataEnabled，在设置数据网络成功开关后，这里通过State.ON : State.OFF状态来控制图标亮暗，所以问题大概率出现在State.ON ，State.OFF这里

```
public void onMobileDataEnabled(boolean enabled) {
        mState = enabled ? State.ON : State.OFF;
    }
```

通过查看State.ON ，State.OFF是在QuickSettingGridAdapter这里定义的

packages\apps\Car\Settings\src\com\android\car\settings\quicksettings\QuickSettingGridAdapter.java

```
public class QuickSettingGridAdapter
        extends RecyclerView.Adapter<RecyclerView.ViewHolder> implements StateChangedListener {
    private static final int SEEKBAR_VIEWTYPE = 0;
    private static final int TILE_VIEWTYPE = 1;
    private final int mColumnCount;
    private final Context mContext;
    private final LayoutInflater mInflater;
    private final List<Tile> mTiles = new ArrayList<>();
    private final List<SeekbarTile> mSeekbarTiles = new ArrayList<>();
    private final QsSpanSizeLookup mQsSpanSizeLookup = new QsSpanSizeLookup();

    public QuickSettingGridAdapter(Context context) {
        mContext = context;
        mInflater = LayoutInflater.from(context);
        mColumnCount = mContext.getResources().getInteger(R.integer.quick_setting_column_count);
    }

    GridLayoutManager getGridLayoutManager() {
        GridLayoutManager gridLayoutManager = new GridLayoutManager(mContext,
                mContext.getResources().getInteger(R.integer.quick_setting_column_count));
        gridLayoutManager.setSpanSizeLookup(mQsSpanSizeLookup);
        return gridLayoutManager;
    }

    /**
     * Represents an UI tile in the quick setting grid.
     */
    interface Tile extends View.OnClickListener {

        /**
         * A state to indicate how we want to render icon, this is independent of what to show
         * in text.
         */
        enum State {
            OFF, ON
        }

        /**
         * Called when activity owning this tile's onStart() gets called.
         */
        void start();

        /**
         * Called when activity owning this tile's onStop() gets called.
         */
        void stop();

        Drawable getIcon();

        @Nullable
        String getText();

        State getState();

        /**
         * Returns {@code true} if this tile should be displayed.
         */
        boolean isAvailable();

        /**
         * Returns a listener to call when this tile is clicked and held. Returns {@code null} if
         * no action should be performed.
         */
        @Nullable
        View.OnLongClickListener getOnLongClickListener();
    }

    interface SeekbarTile extends SeekBar.OnSeekBarChangeListener {
        /**
         * Called when activity owning this tile's onStart() gets called.
         */
        void start();

        /**
         * Called when activity owning this tile's onStop() gets called.
         */
        void stop();

        int getMax();

        int getCurrent();
    }

    QuickSettingGridAdapter addSeekbarTile(SeekbarTile seekbarTile) {
        mSeekbarTiles.add(seekbarTile);
        return this;
    }

    QuickSettingGridAdapter addTile(Tile tile) {
        if (tile.isAvailable()) {
            mTiles.add(tile);
        }
        return this;
    }

    void start() {
        for (SeekbarTile tile : mSeekbarTiles) {
            tile.start();
        }
        for (Tile tile : mTiles) {
            tile.start();
        }
    }

    void stop() {
        for (SeekbarTile tile : mSeekbarTiles) {
            tile.stop();
        }
        for (Tile tile : mTiles) {
            tile.stop();
        }
    }

    @Override
    public RecyclerView.ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
        switch (viewType) {
            case SEEKBAR_VIEWTYPE:
                return new BrightnessViewHolder(mInflater.inflate(
                        R.layout.brightness_tile, parent, /* attachToRoot= */ false));
            case TILE_VIEWTYPE:
                return new TileViewHolder(mInflater.inflate(
                        R.layout.tile, parent, /* attachToRoot= */ false));
            default:
                throw new RuntimeException("unknown viewType: " + viewType);
        }
    }

    @Override
    public void onBindViewHolder(RecyclerView.ViewHolder holder, int position) {
        switch (holder.getItemViewType()) {
            case SEEKBAR_VIEWTYPE:
                SeekbarTile seekbarTile = mSeekbarTiles.get(position);
                SeekBar seekbar = ((BrightnessViewHolder) holder).mSeekBar;
                seekbar.setMax(seekbarTile.getMax());
                seekbar.setProgress(seekbarTile.getCurrent());
                seekbar.setOnSeekBarChangeListener(seekbarTile);
                break;
            case TILE_VIEWTYPE:
                Tile tile = mTiles.get(position - mSeekbarTiles.size());
                TileViewHolder vh = (TileViewHolder) holder;
                vh.itemView.setOnClickListener(tile);
                View.OnLongClickListener onLongClickListener = tile.getOnLongClickListener();
                if (onLongClickListener != null) {
                    vh.itemView.setOnLongClickListener(onLongClickListener);
                } else {
                    vh.itemView.setOnLongClickListener(null);
                }
                vh.mIcon.setImageDrawable(tile.getIcon());
                Log.d("----------wkx--------","adapter");
                switch (tile.getState()) {
                    case ON:
                        vh.mIcon.setEnabled(true);
                        vh.mIconBackground.setEnabled(true);
                        Log.d("----------wkx--------","adapter:getState true");
                        break;
                    case OFF:
                        vh.mIcon.setEnabled(false);
                        vh.mIconBackground.setEnabled(false);
                        Log.d("----------wkx--------","adapter:getState false");
                        break;
                    default:
                }
                String textString = tile.getText();
                if (!TextUtils.isEmpty(textString)) {
                    vh.mText.setText(textString);
                }
                break;
            default:
        }
    }

    private class BrightnessViewHolder extends RecyclerView.ViewHolder {
        private final SeekBar mSeekBar;

        BrightnessViewHolder(View view) {
            super(view);
            mSeekBar = (SeekBar) view.findViewById(R.id.seekbar);
        }
    }

    private class TileViewHolder extends RecyclerView.ViewHolder {
        private final View mIconBackground;
        private final ImageView mIcon;
        private final TextView mText;

        TileViewHolder(View view) {
            super(view);
            mIconBackground = view.findViewById(R.id.icon_background);
            mIcon = view.findViewById(R.id.tile_icon);
            mText = view.findViewById(R.id.tile_text);
        }
    }

    class QsSpanSizeLookup extends GridLayoutManager.SpanSizeLookup {

        /**
         * Each list item takes a full row, and each tile takes only 1 span.
         */
        @Override
        public int getSpanSize(int position) {
            return position < mSeekbarTiles.size() ? mColumnCount : 1;
        }

        @Override
        public int getSpanIndex(int position, int spanCount) {
            return position < mSeekbarTiles.size()
                    ? 1 : (position - mSeekbarTiles.size()) % mColumnCount;
        }
    }

    @Override
    public int getItemViewType(int position) {
        return position < mSeekbarTiles.size() ? SEEKBAR_VIEWTYPE : TILE_VIEWTYPE;
    }

    @Override
    public int getItemCount() {
        return mTiles.size() + mSeekbarTiles.size();
    }

    @Override
    public void onStateChanged() {
        notifyDataSetChanged();
    }
}
```

这里通过代码分析，关键点在这，这里是获取到State来判断ON，OFF，来绘画图标亮暗，这里添加了打印发现，点击数据网络按钮不会调用这里，点击其他三个按钮会打印4个状态，问题就出在这里，没有实时的去获取State信息，所以会导致不会实时变化，而其他三个能控制他的变化是因为全部都会更新一遍

```
public void onBindViewHolder(RecyclerView.ViewHolder holder, int position) {
      vh.mIcon.setImageDrawable(tile.getIcon());
                Log.d("------------------","adapter");
                switch (tile.getState()) {
                    case ON:
                        vh.mIcon.setEnabled(true);
                        vh.mIconBackground.setEnabled(true);
                        Log.d("------------------","adapter:getState true");
                        break;
                    case OFF:
                        vh.mIcon.setEnabled(false);
                        vh.mIconBackground.setEnabled(false);
                        Log.d("------------------","adapter:getState false");
                        break;
                    default:
                }
                String textString = tile.getText();
                if (!TextUtils.isEmpty(textString)) {
                    vh.mText.setText(textString);
                }
                break;
            default:
        }
```

再回到数据网络代码来看，mStateChangedListener = stateChangedListener;这里声明了这个但是没有用到，所以在回调那里添加一个mStateChangedListener.onStateChanged();方法来监听state的变化，最后通过验证是成功的

```
CelluarTile(Context context, StateChangedListener stateChangedListener,
            FragmentHost fragmentHost) {
        mStateChangedListener = stateChangedListener;
        mContext = context;
        TelephonyManager manager =
                (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
        mDataUsageController = new DataUsageController(mContext);
        mDataUsageController.setCallback(this);
        mAvailable = mDataUsageController.isMobileDataSupported();
        mState = mAvailable && mDataUsageController.isMobileDataEnabled() ? State.ON : State.OFF;
        mCarrierName = mAvailable ? manager.getNetworkOperatorName() : null;

        mLaunchDisplaySettings = v -> {
            context.startActivity(new Intent(context,
                    CarSettingActivities.MobileNetworkActivity.class));
            return true;
        };
    }
public void onMobileDataEnabled(boolean enabled) {
        mState = enabled ? State.ON : State.OFF;
        // 我们在回调这里添加一个监听
        mStateChangedListener.onStateChanged();
    }

```