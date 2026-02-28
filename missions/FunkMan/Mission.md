## **📋 MISSION EDITOR SETUP**

---

### **1️⃣ Carrier-Gruppe (USS Stennis + Lake Erie)**

| **Eigenschaft** | **Wert** |
|----------------|-------------|
| **Kategorie** | Ship |
| **Koalition** | Blue |
| **Land** | USA |
| **Gruppenname** | `USS Stennis` |
| **Spät aktiviert** | ❌ NEIN |

**Units in dieser Gruppe:**

| **Unit #** | **Unit Name** | **Typ** |
|--------|-------------|-----------------|
| 1 | `USS Stennis` | CVN-74 Stennis |
| 2 | `Lake Erie` | CG-70 Lake Erie |

---

### **2️⃣ Recovery Tanker (S-3B)**

| **Eigenschaft** | **Wert** |
|----------------|--------------|
| **Kategorie** | Aircraft |
| **Koalition** | Blue |
| **Land** | USA |
| **Typ** | S-3B |
| **Gruppenname** | `Texaco Group` |
| **Unit Name** | `Texaco Group` |
| **Spät aktiviert** | ✅ JA |

---

### **3️⃣ AWACS (E-2D)**

| **Eigenschaft** | **Wert** |
|----------------|-------------------|
| **Kategorie** | Aircraft |
| **Koalition** | Blue |
| **Land** | USA |
| **Typ** | E-2C Hawkeye |
| **Gruppenname** | `E-2D Wizard Group` |
| **Unit Name** | `E-2D Wizard Group` |
| **Spät aktiviert** | ✅ JA |

---

### **4️⃣ Rescue Helo**

| **Eigenschaft** | **Wert** |
|----------------|----------------|
| **Kategorie** | Helicopter |
| **Koalition** | Blue |
| **Land** | USA |
| **Typ** | SH-60B Seahawk |
| **Gruppenname** | `Rescue Helo` |
| **Unit Name** | `Rescue Helo` |
| **Spät aktiviert** | ✅ JA |

---

### **5️⃣ AI Traffic Gruppen**

| **Gruppenname** | **Unit Name** | **Typ** | **Anzahl** | **Spät aktiviert** |
|----------------|----------------|---------|--------|----------------|
| `FA-18C Group 1` | `FA-18C Group 1` | F/A-18C | 1 | ✅ JA |
| `FA-18C Group 2` | `FA-18C Group 2` | F/A-18C | 1 | ✅ JA |
| `FA-18C Group 3` | `FA-18C Group 3` | F/A-18C | 1 | ✅ JA |
| `F-14B 2ship` | `F-14B 2ship` | F-14B | 2 | ✅ JA |
| `E-2D Group` | `E-2D Group` | E-2C | 1 | ✅ JA |
| `S-3B Group` | `S-3B Group` | S-3B | 1 | ✅ JA |

---

### **6️⃣ Goldwater Range - Strafe Pits**

| **Unit Name** | **Typ** | **Spät aktiviert** |
|------------------------|----------------------|----------------|
| `GWR Strafe Pit Left 1` | Fahrzeug oder Static | ❌ NEIN |
| `GWR Strafe Pit Left 2` | Fahrzeug oder Static | ❌ NEIN |
| `GWR Strafe Pit Right 1` | Fahrzeug oder Static | ❌ NEIN |
| `GWR Strafe Pit Right 2` | Fahrzeug oder Static | ❌ NEIN |
| `GWR Foul Line Left` | Static Object | ❌ NEIN |

---

### **7️⃣ Goldwater Range - Bomb Targets**

| **Unit Name** | **Typ** | **Spät aktiviert** |
|------------------------------|---------------|----------------|
| `GWR Bomb Target Circle Left` | Static Object | ❌ NEIN |
| `GWR Bomb Target Circle Right` | Static Object | ❌ NEIN |
| `GWR Bomb Target Hard` | Static Object | ❌ NEIN |

---

## **🎯 ÜBERSICHT ALLER EINHEITEN**

| **Einheit** | **Gruppenname** | **Unit Name** | **Late Activation** |
|---------------|-------------------|------------------------------|-----------------|
| Carrier | `USS Stennis` | `USS Stennis` | ❌ |
| Escort | `USS Stennis` | `Lake Erie` | ❌ |
| Tanker | `Texaco Group` | `Texaco Group` | ✅ |
| AWACS | `E-2D Wizard Group` | `E-2D Wizard Group` | ✅ |
| Rescue Helo | `Rescue Helo` | `Rescue Helo` | ✅ |
| AI F/A-18C #1 | `FA-18C Group 1` | `FA-18C Group 1` | ✅ |
| AI F/A-18C #2 | `FA-18C Group 2` | `FA-18C Group 2` | ✅ |
| AI F/A-18C #3 | `FA-18C Group 3` | `FA-18C Group 3` | ✅ |
| AI F-14B | `F-14B 2ship` | `F-14B 2ship` | ✅ |
| AI E-2D | `E-2D Group` | `E-2D Group` | ✅ |
| AI S-3B | `S-3B Group` | `S-3B Group` | ✅ |
| Strafe Target | \- | `GWR Strafe Pit Left 1` | ❌ |
| Strafe Target | \- | `GWR Strafe Pit Left 2` | ❌ |
| Strafe Target | \- | `GWR Strafe Pit Right 1` | ❌ |
| Strafe Target | \- | `GWR Strafe Pit Right 2` | ❌ |
| Foul Line | \- | `GWR Foul Line Left` | ❌ |
| Bomb Target | \- | `GWR Bomb Target Circle Left` | ❌ |
| Bomb Target | \- | `GWR Bomb Target Circle Right` | ❌ |
| Bomb Target | \- | `GWR Bomb Target Hard` | ❌ |

---

## **🔧 FUNKMAN**

**Aktiviert für:**

- Airboss (Zeile 40)
- Range (Zeile 154)

**Voraussetzung:** FunkMan muss **vor** Missionsstart laufen:

```
textHost: 127.0.0.1
Port: 10043
```

---

## **📂 SOUNDFILES**

| **Ordner** | **Verwendet in Zeile** |
|---------------------|--------------------|
| `Airboss Soundfiles/` | 53 |
| `Range Soundfiles/` | 148 |

---

## **📝 TRIGGER SETUP**

| **Nr** | **Typ** | **Condition** | **Action** |
|----|---------------|-------------|----------------------------------|
| 1 | MISSION START | TIME MORE 1 | DO SCRIPT FILE → `Moose.lua` |
| 2 | MISSION START | TIME MORE 2 | DO SCRIPT FILE → `dein_script.lua` |

---

## **✅ CHECKLISTE**

### **Carrier-Gruppe (NICHT late activated)**

- [ ] Gruppenname = `USS Stennis`
- [ ] Unit 1: Unit Name = `USS Stennis` (CVN-74)
- [ ] Unit 2: Unit Name = `Lake Erie` (CG-70)

### **Flugzeuge (alle late activated ✅)**

- [ ] `Texaco Group` (S-3B)
- [ ] `E-2D Wizard Group` (E-2C)
- [ ] `Rescue Helo` (SH-60B)
- [ ] `FA-18C Group 1` (F/A-18C)
- [ ] `FA-18C Group 2` (F/A-18C)
- [ ] `FA-18C Group 3` (F/A-18C)
- [ ] `F-14B 2ship` (F-14B, 2 Units)
- [ ] `E-2D Group` (E-2C)
- [ ] `S-3B Group` (S-3B)

### **Range Objekte (NICHT late activated)**

- [ ] `GWR Strafe Pit Left 1`
- [ ] `GWR Strafe Pit Left 2`
- [ ] `GWR Strafe Pit Right 1`
- [ ] `GWR Strafe Pit Right 2`
- [ ] `GWR Foul Line Left`
- [ ] `GWR Bomb Target Circle Left`
- [ ] `GWR Bomb Target Circle Right`
- [ ] `GWR Bomb Target Hard`