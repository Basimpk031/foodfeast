import { useState } from "react";

const COLORS = {
  dark: "#0D1B2A",
  accent: "#0077B6",
  teal: "#00C9A7",
  bg: "#F2F2F7",
  white: "#FFFFFF",
  text: "#1C1C1E",
  subtext: "#8E8E93",
  pending: "#FF9500",
  delivered: "#34C759",
  red: "#FF3B30",
};

const initialMenuItems = [
  { id: 1, name: "Burger", price: 70, calories: 300, protein: 30, carbs: 40, fat: 50, veg: false, enabled: true, image: "🍔" },
  { id: 2, name: "Veg Burger", price: 60, calories: 200, protein: 20, carbs: 30, fat: 5, veg: true, enabled: true, image: "🥬" },
  { id: 3, name: "Boba Tea", price: 169, calories: 250, protein: 0, carbs: 40, fat: 0, veg: true, enabled: true, image: "🧋" },
];

const initialOrders = [
  { id: "ORD001", customer: "Rahul S.", items: [{ name: "Burger", qty: 2, price: 70 }], total: 140, status: "pending", time: "2m ago", address: "12, MG Road, Bengaluru" },
  { id: "ORD002", customer: "Priya M.", items: [{ name: "Veg Burger", qty: 1, price: 60 }, { name: "Boba Tea", qty: 2, price: 169 }], total: 398, status: "confirmed", time: "8m ago", address: "45, Koramangala, Bengaluru" },
  { id: "ORD003", customer: "Amit K.", items: [{ name: "Burger", qty: 3, price: 70 }], total: 210, status: "preparing", time: "15m ago", address: "7, HSR Layout, Bengaluru" },
  { id: "ORD004", customer: "Sneha R.", items: [{ name: "Boba Tea", qty: 1, price: 169 }], total: 169, status: "delivered", time: "1h ago", address: "3, Indiranagar, Bengaluru" },
];

const statusColors = {
  pending: "#FF9500",
  confirmed: "#0077B6",
  preparing: "#AF52DE",
  delivered: "#34C759",
  cancelled: "#FF3B30",
};

function Badge({ label, color }) {
  return (
    <span style={{
      background: color + "18",
      color,
      fontSize: 10,
      fontWeight: 700,
      padding: "2px 7px",
      borderRadius: 6,
      display: "inline-block",
    }}>{label}</span>
  );
}

function Toggle({ checked, onChange }) {
  return (
    <div onClick={onChange} style={{
      width: 48, height: 28, borderRadius: 14,
      background: checked ? COLORS.teal : "#C7C7CC",
      position: "relative", cursor: "pointer",
      transition: "background 0.2s",
      flexShrink: 0,
    }}>
      <div style={{
        position: "absolute", top: 3,
        left: checked ? 23 : 3,
        width: 22, height: 22,
        borderRadius: "50%", background: "#fff",
        boxShadow: "0 1px 4px rgba(0,0,0,0.25)",
        transition: "left 0.2s",
      }} />
    </div>
  );
}

function TopBar({ onLogout }) {
  return (
    <div style={{
      background: COLORS.dark,
      padding: "0 20px",
      height: 60,
      display: "flex", alignItems: "center", justifyContent: "space-between",
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <div style={{
          width: 34, height: 34, borderRadius: 8,
          background: COLORS.teal + "22",
          border: `1.5px solid ${COLORS.teal}55`,
          display: "flex", alignItems: "center", justifyContent: "center",
          fontSize: 18,
        }}>🏪</div>
        <span style={{ color: "#fff", fontWeight: 800, fontSize: 18, letterSpacing: -0.5 }}>
          Food<span style={{ color: COLORS.teal }}>Feast</span>{" "}
          <span style={{ color: COLORS.accent, fontWeight: 600, fontSize: 14 }}>Restaurant</span>
        </span>
      </div>
      <button onClick={onLogout} style={{
        background: "none", border: "none", cursor: "pointer",
        color: "#ffffff88", fontSize: 20, padding: 4,
      }}>⬚</button>
    </div>
  );
}

function TabBar({ activeTab, setActiveTab }) {
  const tabs = [
    { id: "restaurant", label: "My Restaurant", icon: "🏪" },
    { id: "menu", label: "Menu Items", icon: "🍴" },
    { id: "orders", label: "Orders", icon: "📋" },
  ];
  return (
    <div style={{
      background: COLORS.dark,
      display: "flex",
      borderBottom: `2px solid #ffffff11`,
    }}>
      {tabs.map(t => (
        <button key={t.id} onClick={() => setActiveTab(t.id)} style={{
          flex: 1, padding: "12px 0",
          background: "none", border: "none", cursor: "pointer",
          color: activeTab === t.id ? COLORS.teal : "#ffffff66",
          fontWeight: activeTab === t.id ? 700 : 500,
          fontSize: 13,
          borderBottom: activeTab === t.id ? `2.5px solid ${COLORS.teal}` : "2.5px solid transparent",
          transition: "all 0.15s",
          display: "flex", alignItems: "center", justifyContent: "center", gap: 6,
        }}>
          <span style={{ fontSize: 14 }}>{t.icon}</span>
          {t.label}
        </button>
      ))}
    </div>
  );
}

// ─── MY RESTAURANT TAB ───────────────────────────────────────────
function MyRestaurantTab({ isOpen, setIsOpen, orders, onNavigateOrders }) {
  const todayOrders = orders.length;
  const revenue = orders.reduce((s, o) => s + o.total, 0);
  const pending = orders.filter(o => o.status === "pending").length;
  const delivered = orders.filter(o => o.status === "delivered").length;

  return (
    <div style={{ padding: "16px" }}>
      {/* Restaurant Card */}
      <div style={{
        background: "#fff", borderRadius: 18,
        overflow: "hidden",
        boxShadow: "0 2px 12px rgba(0,0,0,0.07)",
        marginBottom: 18,
      }}>
        <div style={{
          height: 160,
          background: "linear-gradient(135deg, #1a2a3a 0%, #0D1B2A 100%)",
          display: "flex", alignItems: "center", justifyContent: "center",
          fontSize: 60,
          position: "relative",
          overflow: "hidden",
        }}>
          <div style={{
            position: "absolute", inset: 0,
            background: "linear-gradient(135deg, #0077B622 0%, #00C9A722 100%)",
          }} />
          <span style={{ position: "relative", filter: "drop-shadow(0 2px 8px #0005)" }}>🍔</span>
          <div style={{
            position: "absolute", top: 0, left: 0, right: 0, bottom: 0,
            backgroundImage: "radial-gradient(circle at 80% 20%, #00C9A711 0%, transparent 60%)",
          }} />
        </div>
        <div style={{ padding: "14px 16px", display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
          <div>
            <div style={{ fontWeight: 800, fontSize: 19, color: COLORS.text }}>Kismath cafe</div>
            <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 4 }}>
              <span style={{ fontSize: 12, color: COLORS.subtext }}>🏪 Burger</span>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 4, marginTop: 4 }}>
              <span style={{ fontSize: 12, color: COLORS.subtext }}>⏱ 2</span>
              <span style={{ fontSize: 13 }}>⭐</span>
              <span style={{ fontWeight: 700, fontSize: 13, color: COLORS.text }}>4.0</span>
            </div>
          </div>
          <span style={{
            background: COLORS.delivered + "18",
            color: COLORS.delivered,
            fontWeight: 700, fontSize: 12,
            padding: "4px 12px", borderRadius: 20,
            border: `1px solid ${COLORS.delivered}44`,
          }}>Active</span>
        </div>
      </div>

      {/* Quick Controls */}
      <div style={{ fontWeight: 800, fontSize: 16, color: COLORS.text, marginBottom: 12 }}>Quick Controls</div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 22 }}>
        <div style={{
          background: "#fff", borderRadius: 14, padding: "16px",
          boxShadow: "0 2px 8px rgba(0,0,0,0.06)",
        }}>
          <Toggle checked={isOpen} onChange={() => setIsOpen(!isOpen)} />
          <div style={{ fontWeight: 700, fontSize: 14, color: isOpen ? COLORS.teal : COLORS.red, marginTop: 10 }}>
            {isOpen ? "Restaurant is Open" : "Restaurant is Closed"}
          </div>
          <div style={{ fontSize: 12, color: COLORS.subtext, marginTop: 2 }}>
            Tap to {isOpen ? "close" : "open"}
          </div>
        </div>
        <div style={{
          background: "#fff", borderRadius: 14, padding: "16px",
          boxShadow: "0 2px 8px rgba(0,0,0,0.06)",
          cursor: "pointer",
        }}>
          <span style={{ fontSize: 22, color: COLORS.accent }}>✏️</span>
          <div style={{ fontWeight: 700, fontSize: 14, color: COLORS.accent, marginTop: 10 }}>Edit Details</div>
          <div style={{ fontSize: 12, color: COLORS.subtext, marginTop: 2 }}>Name, image, hours</div>
        </div>
      </div>

      {/* Today at a Glance */}
      <div style={{ fontWeight: 800, fontSize: 16, color: COLORS.text, marginBottom: 12 }}>Today at a Glance</div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr", gap: 10 }}>
        {[
          { icon: "📋", value: todayOrders, label: "Today's Orders", color: COLORS.accent, filter: "all" },
          { icon: "₹", value: `₹${revenue}`, label: "Revenue", color: COLORS.teal, filter: null },
          { icon: "⏳", value: pending, label: "Pending", color: COLORS.pending, filter: "pending" },
          { icon: "✅", value: delivered, label: "Delivered", color: COLORS.delivered, filter: "delivered" },
        ].map((s, i) => (
          <div key={i}
            onClick={() => s.filter !== null && onNavigateOrders(s.filter)}
            style={{
              background: "#fff", borderRadius: 14, padding: "14px 8px",
              boxShadow: "0 2px 8px rgba(0,0,0,0.06)",
              textAlign: "center",
              cursor: s.filter !== null ? "pointer" : "default",
              transition: "transform 0.12s, box-shadow 0.12s",
              position: "relative",
            }}
            onMouseDown={e => { if (s.filter) e.currentTarget.style.transform = "scale(0.95)"; }}
            onMouseUp={e => { e.currentTarget.style.transform = "scale(1)"; }}
            onMouseLeave={e => { e.currentTarget.style.transform = "scale(1)"; }}
          >
            <div style={{ fontSize: 20, marginBottom: 6 }}>{s.icon}</div>
            <div style={{ fontWeight: 800, fontSize: 18, color: s.color }}>{s.value}</div>
            <div style={{ fontSize: 10, color: COLORS.subtext, marginTop: 3 }}>{s.label}</div>
            {s.filter !== null && (
              <div style={{
                position: "absolute", bottom: 6, right: 8,
                fontSize: 9, color: s.color + "99", fontWeight: 700,
              }}>→</div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── MENU ITEMS TAB ──────────────────────────────────────────────
function MenuItemsTab() {
  const [items, setItems] = useState(initialMenuItems);
  const [showAdd, setShowAdd] = useState(false);
  const [newItem, setNewItem] = useState({ name: "", price: "", calories: "", protein: "", carbs: "", fat: "", veg: false });

  const toggleItem = (id) => setItems(items.map(i => i.id === id ? { ...i, enabled: !i.enabled } : i));
  const deleteItem = (id) => setItems(items.filter(i => i.id !== id));
  const addItem = () => {
    if (!newItem.name || !newItem.price) return;
    setItems([...items, { ...newItem, id: Date.now(), price: +newItem.price, calories: +newItem.calories, protein: +newItem.protein, carbs: +newItem.carbs, fat: +newItem.fat, enabled: true, image: newItem.veg ? "🥗" : "🍖" }]);
    setNewItem({ name: "", price: "", calories: "", protein: "", carbs: "", fat: "", veg: false });
    setShowAdd(false);
  };

  return (
    <div style={{ padding: 16 }}>
      {items.map(item => (
        <div key={item.id} style={{
          background: "#fff", borderRadius: 16, padding: 16,
          marginBottom: 12, boxShadow: "0 2px 10px rgba(0,0,0,0.06)",
          display: "flex", gap: 12, alignItems: "flex-start",
        }}>
          <div style={{
            width: 72, height: 72, borderRadius: 12,
            background: "linear-gradient(135deg, #f5f5f7, #e8e8ee)",
            display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: 36, flexShrink: 0,
          }}>{item.image}</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 800, fontSize: 15, color: COLORS.text }}>{item.name}</div>
            <div style={{ display: "flex", gap: 6, alignItems: "center", marginTop: 3 }}>
              <span style={{ fontWeight: 700, fontSize: 14, color: COLORS.accent }}>₹{item.price}</span>
              <span style={{ fontSize: 12, color: COLORS.subtext }}>🔥 {item.calories} kcal</span>
            </div>
            <div style={{ display: "flex", gap: 4, flexWrap: "wrap", marginTop: 6 }}>
              {item.protein > 0 && <Badge label={`P:${item.protein}g`} color={COLORS.accent} />}
              {item.carbs > 0 && <Badge label={`C:${item.carbs}g`} color={COLORS.teal} />}
              {item.fat > 0 && <Badge label={`F:${item.fat}g`} color={COLORS.pending} />}
            </div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 10 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <div style={{
                width: 16, height: 16, borderRadius: 3,
                border: `2px solid ${item.veg ? COLORS.teal : COLORS.red}`,
                display: "flex", alignItems: "center", justifyContent: "center",
              }}>
                <div style={{ width: 8, height: 8, borderRadius: "50%", background: item.veg ? COLORS.teal : COLORS.red }} />
              </div>
              <Toggle checked={item.enabled} onChange={() => toggleItem(item.id)} />
            </div>
            <div style={{ display: "flex", gap: 12 }}>
              <button style={{ background: "none", border: "none", cursor: "pointer", fontSize: 16, color: COLORS.subtext }}>✏️</button>
              <button onClick={() => deleteItem(item.id)} style={{ background: "none", border: "none", cursor: "pointer", fontSize: 16, color: COLORS.red }}>🗑️</button>
            </div>
          </div>
        </div>
      ))}

      {showAdd && (
        <div style={{
          background: "#fff", borderRadius: 16, padding: 16,
          marginBottom: 12, boxShadow: "0 2px 10px rgba(0,0,0,0.08)",
        }}>
          <div style={{ fontWeight: 700, fontSize: 15, marginBottom: 12 }}>New Menu Item</div>
          {[
            { key: "name", placeholder: "Item name", type: "text" },
            { key: "price", placeholder: "Price (₹)", type: "number" },
            { key: "calories", placeholder: "Calories (kcal)", type: "number" },
            { key: "protein", placeholder: "Protein (g)", type: "number" },
            { key: "carbs", placeholder: "Carbs (g)", type: "number" },
            { key: "fat", placeholder: "Fat (g)", type: "number" },
          ].map(f => (
            <input key={f.key} type={f.type} placeholder={f.placeholder} value={newItem[f.key]}
              onChange={e => setNewItem({ ...newItem, [f.key]: e.target.value })}
              style={{
                width: "100%", padding: "10px 12px", borderRadius: 10,
                border: "1.5px solid #E5E5EA", marginBottom: 8,
                fontSize: 14, outline: "none", boxSizing: "border-box",
              }} />
          ))}
          <label style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12, cursor: "pointer" }}>
            <Toggle checked={newItem.veg} onChange={() => setNewItem({ ...newItem, veg: !newItem.veg })} />
            <span style={{ fontSize: 13, color: COLORS.text }}>Vegetarian</span>
          </label>
          <div style={{ display: "flex", gap: 10 }}>
            <button onClick={addItem} style={{
              flex: 1, padding: "12px", borderRadius: 12, border: "none",
              background: COLORS.accent, color: "#fff", fontWeight: 700, cursor: "pointer",
            }}>Add Item</button>
            <button onClick={() => setShowAdd(false)} style={{
              flex: 1, padding: "12px", borderRadius: 12, border: "none",
              background: "#F2F2F7", color: COLORS.text, fontWeight: 700, cursor: "pointer",
            }}>Cancel</button>
          </div>
        </div>
      )}

      <button onClick={() => setShowAdd(true)} style={{
        position: "fixed", bottom: 28, right: 20,
        background: COLORS.accent, color: "#fff",
        border: "none", borderRadius: 16, padding: "14px 24px",
        fontWeight: 700, fontSize: 15, cursor: "pointer",
        display: "flex", alignItems: "center", gap: 8,
        boxShadow: `0 6px 20px ${COLORS.accent}55`,
      }}>
        <span style={{ fontSize: 18 }}>+</span> Add Item
      </button>
    </div>
  );
}

// ─── ORDERS TAB ──────────────────────────────────────────────────
function OrdersTab({ initialFilter = "all" }) {
  const [filter, setFilter] = useState(initialFilter);
  const [orders, setOrders] = useState(initialOrders);

  const filters = ["all", "pending", "confirmed", "preparing", "delivered"];
  const visible = filter === "all" ? orders : orders.filter(o => o.status === filter);

  const updateStatus = (id, status) => setOrders(orders.map(o => o.id === id ? { ...o, status } : o));

  return (
    <div>
      {/* Filter chips */}
      <div style={{
        display: "flex", gap: 8, padding: "14px 16px 10px",
        overflowX: "auto", background: "#fff",
        borderBottom: "1px solid #F2F2F7",
      }}>
        {filters.map(f => (
          <button key={f} onClick={() => setFilter(f)} style={{
            padding: "7px 16px", borderRadius: 20, border: "1.5px solid",
            borderColor: filter === f ? COLORS.accent : "#E5E5EA",
            background: filter === f ? COLORS.accent : "#fff",
            color: filter === f ? "#fff" : COLORS.subtext,
            fontWeight: 600, fontSize: 13, cursor: "pointer",
            whiteSpace: "nowrap", flexShrink: 0,
          }}>
            {f.charAt(0).toUpperCase() + f.slice(1)}
          </button>
        ))}
      </div>

      <div style={{ padding: 16 }}>
        {visible.length === 0 ? (
          <div style={{
            display: "flex", flexDirection: "column", alignItems: "center",
            justifyContent: "center", height: 300, color: COLORS.subtext,
          }}>
            <div style={{ fontSize: 60, marginBottom: 16 }}>📋</div>
            <div style={{ fontSize: 16, fontWeight: 600 }}>No orders yet</div>
          </div>
        ) : visible.map(order => (
          <div key={order.id} style={{
            background: "#fff", borderRadius: 16, marginBottom: 14,
            boxShadow: "0 2px 10px rgba(0,0,0,0.06)", overflow: "hidden",
          }}>
            {/* Header */}
            <div style={{
              padding: "12px 16px",
              borderLeft: `4px solid ${statusColors[order.status]}`,
              display: "flex", justifyContent: "space-between", alignItems: "center",
            }}>
              <div>
                <span style={{ fontWeight: 800, fontSize: 14, color: COLORS.text }}>{order.id}</span>
                <span style={{ fontSize: 12, color: COLORS.subtext, marginLeft: 8 }}>{order.time}</span>
              </div>
              <span style={{
                background: statusColors[order.status] + "18",
                color: statusColors[order.status],
                fontWeight: 700, fontSize: 11, padding: "3px 10px", borderRadius: 8,
                textTransform: "capitalize",
              }}>{order.status}</span>
            </div>

            <div style={{ borderTop: "1px solid #F2F2F7" }} />

            {/* Customer & Items */}
            <div style={{ padding: "10px 16px" }}>
              <div style={{ fontWeight: 600, fontSize: 13, color: COLORS.text, marginBottom: 6 }}>
                👤 {order.customer}
              </div>
              {order.items.map((item, i) => (
                <div key={i} style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                  <span style={{ fontSize: 12.5, color: COLORS.text }}>• {item.name} ×{item.qty}</span>
                  <span style={{ fontSize: 12.5, color: COLORS.red, fontWeight: 700 }}>₹{item.price * item.qty}</span>
                </div>
              ))}
              <div style={{ fontSize: 11.5, color: COLORS.subtext, marginTop: 6 }}>
                📍 {order.address}
              </div>
            </div>

            {/* Footer */}
            <div style={{
              padding: "10px 16px 14px",
              borderTop: "1px solid #F2F2F7",
              display: "flex", justifyContent: "space-between", alignItems: "center",
            }}>
              <select value={order.status} onChange={e => updateStatus(order.id, e.target.value)} style={{
                padding: "6px 12px", borderRadius: 10,
                border: `1.5px solid ${statusColors[order.status]}44`,
                background: statusColors[order.status] + "10",
                color: statusColors[order.status],
                fontWeight: 700, fontSize: 12,
                cursor: "pointer", outline: "none",
              }}>
                {["pending","confirmed","preparing","delivered","cancelled"].map(s => (
                  <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>
                ))}
              </select>
              <span style={{ fontWeight: 800, fontSize: 15, color: COLORS.text }}>
                ₹{order.total}
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── MAIN APP ────────────────────────────────────────────────────
export default function App() {
  const [activeTab, setActiveTab] = useState("restaurant");
  const [ordersFilter, setOrdersFilter] = useState("all");
  const [isOpen, setIsOpen] = useState(true);
  const [loggedIn, setLoggedIn] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPw, setShowPw] = useState(false);
  const [loading, setLoading] = useState(false);

  const handleNavigateOrders = (filter) => {
    setOrdersFilter(filter);
    setActiveTab("orders");
  };

  const handleTabChange = (tab) => {
    if (tab !== "orders") setOrdersFilter("all");
    setActiveTab(tab);
  };

  const handleLogin = () => {
    if (!email || !password) return;
    setLoading(true);
    setTimeout(() => { setLoading(false); setLoggedIn(true); }, 1200);
  };

  if (!loggedIn) return (
    <div style={{
      minHeight: "100vh", background: COLORS.dark,
      display: "flex", flexDirection: "column", alignItems: "center",
      justifyContent: "center", padding: 28,
      position: "relative", overflow: "hidden",
    }}>
      <div style={{
        position: "absolute", top: -80, right: -80, width: 250, height: 250,
        borderRadius: "50%", background: COLORS.teal + "0d",
      }} />
      <div style={{
        position: "absolute", bottom: -60, left: -60, width: 200, height: 200,
        borderRadius: "50%", background: COLORS.accent + "0d",
      }} />
      <div style={{
        width: 80, height: 80, borderRadius: "50%",
        background: COLORS.teal + "22",
        border: `2px solid ${COLORS.teal}55`,
        display: "flex", alignItems: "center", justifyContent: "center",
        fontSize: 38, marginBottom: 20,
      }}>🏪</div>
      <div style={{ color: "#fff", fontWeight: 800, fontSize: 26, letterSpacing: -0.5, marginBottom: 6 }}>Restaurant Portal</div>
      <div style={{ color: "#ffffff66", fontSize: 13.5, marginBottom: 36 }}>Manage your restaurant on FoodFeast</div>
      <div style={{ width: "100%", maxWidth: 380 }}>
        <input value={email} onChange={e => setEmail(e.target.value)} type="email" placeholder="Email address"
          style={{
            width: "100%", padding: "14px 16px", borderRadius: 14,
            border: "1.5px solid #ffffff15", background: "#ffffff0e",
            color: "#fff", fontSize: 14, outline: "none",
            marginBottom: 12, boxSizing: "border-box",
          }} />
        <div style={{ position: "relative", marginBottom: 20 }}>
          <input value={password} onChange={e => setPassword(e.target.value)} type={showPw ? "text" : "password"} placeholder="Password"
            style={{
              width: "100%", padding: "14px 16px", borderRadius: 14,
              border: "1.5px solid #ffffff15", background: "#ffffff0e",
              color: "#fff", fontSize: 14, outline: "none", boxSizing: "border-box",
            }} />
          <button onClick={() => setShowPw(!showPw)} style={{
            position: "absolute", right: 14, top: "50%", transform: "translateY(-50%)",
            background: "none", border: "none", color: "#ffffff55", cursor: "pointer", fontSize: 16,
          }}>{showPw ? "🙈" : "👁"}</button>
        </div>
        <button onClick={handleLogin} style={{
          width: "100%", padding: "15px", borderRadius: 14,
          background: loading ? COLORS.teal + "88" : COLORS.teal,
          border: "none", color: "#fff", fontWeight: 800, fontSize: 15,
          cursor: loading ? "default" : "pointer",
          transition: "background 0.2s",
          boxShadow: `0 4px 16px ${COLORS.teal}44`,
        }}>
          {loading ? "Signing in…" : "Sign In"}
        </button>
      </div>
    </div>
  );

  return (
    <div style={{
      minHeight: "100vh", maxWidth: 430,
      margin: "0 auto", background: COLORS.bg,
      fontFamily: "'SF Pro Display', -apple-system, BlinkMacSystemFont, sans-serif",
    }}>
      <TopBar onLogout={() => setLoggedIn(false)} />
      <TabBar activeTab={activeTab} setActiveTab={handleTabChange} />
      <div style={{ paddingBottom: 80 }}>
        {activeTab === "restaurant" && <MyRestaurantTab isOpen={isOpen} setIsOpen={setIsOpen} orders={initialOrders} onNavigateOrders={handleNavigateOrders} />}
        {activeTab === "menu" && <MenuItemsTab />}
        {activeTab === "orders" && <OrdersTab initialFilter={ordersFilter} />}
      </div>
    </div>
  );
}
