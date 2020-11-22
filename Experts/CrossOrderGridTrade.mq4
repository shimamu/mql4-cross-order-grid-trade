//+------------------------------------------------------------------+
//|                                          CrossOrderGridTrade.mq4 |
//|                                         Copyright 2020, shimamu. |
//|                                       https://github.com/shimamu |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, shimamu."
#property link      "https://github.com/shimamu"
#property version   "1.00"
#property strict

#include <stdlib.mqh>

// Parameter.
extern double Lots = 0.04; // 1 Lot = 100,000 currency.

// Global variables.
int MagicNumber = 20201116;
double GridSpace = 0.25;
int Slippage = 3;
double BuyMaxPrice = 109.95;
double BuyMinPrice = 100.2;
double SellMaxPrice = 114.95;
double SellMinPrice = 104.2;

struct Order {
    int ticket;  // Order number.
    double lots;
    double price;
};

//+------------------------------------------------------------------+
//| Common order rule.                                               |
//+------------------------------------------------------------------+
class OrderRule {
protected:
    int OrderType;
    string OrderTypeLabel;
    double MaxPrice;
    double MinPrice;
    color EntryColor;
    color ExitColor;
    Order last_order;
    double lots_total;
    double next_entry_price;
    double next_exit_price;
    virtual double countEntryLots() = 0;
    virtual double exitRate() = 0;
    virtual double entryRate() = 0;
    virtual bool hasExitSign() = 0;
    virtual bool hasEntrySign() = 0;
    virtual void setNextTargetAfterExit() = 0;
    virtual void setNextTargetAfterEntry() = 0;

    void checkOrder() {
        Order last_order = {};
        double lots_total = 0;
        for (int i = 0; i < OrdersTotal(); i++) {
            bool success = OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
            if (!success) {
                return;
            }

            // Check currency pair.
            if (OrderSymbol() != Symbol()) {
                continue;
            }

            if (OrderMagicNumber() != MagicNumber) {
                continue;
            }

            if (OrderType() == this.OrderType) {
                last_order.ticket = OrderTicket();
                last_order.lots = OrderLots();
                last_order.price = OrderOpenPrice();
                lots_total += OrderLots();
            }
        }
        this.last_order = last_order;
        this.lots_total = lots_total;
    }

    bool hasOrder() {
        if (this.last_order.ticket > 0) {
            return true;
        }
        return false;
    }

    void checkForExit() {
        if (!this.hasOrder()) {
            return;
        }

        if (!this.hasExitSign()) {
            return;
        }

        bool success = OrderClose(
                           this.last_order.ticket,
                           Lots,
                           this.exitRate(),
                           Slippage,
                           this.ExitColor);
        if (success) {
            this.setNextTargetAfterExit();
        } else {
            this.checkError("OrderClose");
            Sleep(1000);
        }
    }

    void checkForEntry() {
        if (!this.hasEntrySign()) {
            return;
        }

        double entry_lots = this.countEntryLots();
        if (entry_lots <= 0) {
            this.setNextTargetAfterEntry();
            return;
        }

        int ticket = OrderSend(
                         Symbol(),
                         this.OrderType,
                         entry_lots,
                         this.entryRate(),
                         Slippage,
                         0,
                         0,
                         NULL,
                         MagicNumber,
                         0,
                         this.EntryColor);
        if (ticket > 0) {
            this.setNextTargetAfterEntry();
        } else {
            this.checkError("OrderSend");
            Sleep(1000);
        }
    }

    void checkError(string msg) {
        int error_code = GetLastError();
        if (error_code != ERR_NO_ERROR) {
            printf(
                "Error in (%s)  code:%d,  detail:%s ",
                msg,
                error_code,
                ErrorDescription(error_code));
        }
    }

    void moveNextTarget(double points) {
        this.next_entry_price += points;
        this.next_exit_price += points;
        printf(
            "-> next %s  entry:%.3f  exit:%.3f",
            this.OrderTypeLabel,
            this.next_entry_price,
            this.next_exit_price);
    }

    void moveNextTargetUp() {
        this.moveNextTarget(GridSpace);
    }

    void moveNextTargetDown() {
        this.moveNextTarget(- GridSpace);
    }

public:
    void run() {
        this.checkOrder();
        this.checkForExit();
        this.checkForEntry();
    }
};

//+------------------------------------------------------------------+
//| Specifics of buy position.                                       |
//+------------------------------------------------------------------+
class BuyOrderRule: public OrderRule {
protected:
    virtual bool hasExitSign() {
        if (Bid < this.next_exit_price) {
            return false;
        }

        if (Bid <= this.last_order.price) {
            this.setNextTargetAfterExit();
            return false;
        }
        return true;
    }

    virtual double exitRate() {
        return Bid;
    }

    virtual void setNextTargetAfterExit() {
        this.moveNextTargetUp();
    }

    virtual double entryRate() {
        return Ask;
    }

    virtual bool hasEntrySign() {
        if (this.MaxPrice < Ask) {
            return false;
        }

        if (Ask < this.MinPrice) {
            return false;
        }

        if (this.next_entry_price < Ask) {
            return false;
        }
        return true;
    }

    virtual void setNextTargetAfterEntry() {
        this.moveNextTargetDown();
    }

    virtual double countEntryLots() {
        if (this.MaxPrice < Ask) {
            return 0;
        }
        int max_position_num = int((this.MaxPrice - Ask) / GridSpace) + 1;
        double max_lots = max_position_num * Lots;
        double need_lots = max_lots - this.lots_total;
        return need_lots;
    }

public:
    void BuyOrderRule(double max_price, double min_price) {
        this.OrderType = OP_BUY;
        this.OrderTypeLabel = "buy";
        this.MaxPrice = max_price;
        this.MinPrice = min_price;
        this.EntryColor = clrAqua;
        this.ExitColor = clrBlue;
        this.next_entry_price = this.MaxPrice;
        this.next_exit_price = this.MaxPrice + GridSpace * 2;
    }
};

//+------------------------------------------------------------------+
//| Specifics of sell position.                                      |
//+------------------------------------------------------------------+
class SellOrderRule: public OrderRule {
protected:
    virtual bool hasExitSign() {
        if (this.next_exit_price < Ask) {
            return false;
        }

        if (this.last_order.price <= Ask) {
            this.setNextTargetAfterExit();
            return false;
        }

        return true;
    }

    virtual double exitRate() {
        return Ask;
    }

    virtual void setNextTargetAfterExit() {
        this.moveNextTargetDown();
    }

    virtual double entryRate() {
        return Bid;
    }

    virtual bool hasEntrySign() {
        if (Bid < this.MinPrice) {
            return false;
        }

        if (this.MaxPrice < Bid) {
            return false;
        }

        if (Bid < this.next_entry_price) {
            return false;
        }
        return true;
    }

    virtual void setNextTargetAfterEntry() {
        this.moveNextTargetUp();
    }

    virtual double countEntryLots() {
        if (Bid < this.MinPrice) {
            return 0;
        }
        int max_position_num = int((Bid - this.MinPrice) / GridSpace) + 1;
        double max_lots = max_position_num * Lots;
        double need_lots = max_lots - this.lots_total;
        return need_lots;
    }

public:
    void SellOrderRule(double max_price, double min_price) {
        this.OrderType = OP_SELL;
        this.OrderTypeLabel = "sell";
        this.MaxPrice = max_price;
        this.MinPrice = min_price;
        this.EntryColor = clrHotPink;
        this.ExitColor = clrRed;
        this.next_entry_price = this.MinPrice;
        this.next_exit_price = this.MinPrice - GridSpace * 2;
    }
};

BuyOrderRule* buy_order_rule;
SellOrderRule* sell_order_rule;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
//---
    buy_order_rule = new BuyOrderRule(BuyMaxPrice, BuyMinPrice);
    sell_order_rule = new SellOrderRule(SellMaxPrice, SellMinPrice);
//---
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
//---

}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    buy_order_rule.run();
    sell_order_rule.run();
}
//+------------------------------------------------------------------+
