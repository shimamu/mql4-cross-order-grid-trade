//+------------------------------------------------------------------+
//|                                          CrossOrderGridTrade.mq4 |
//|                                         Copyright 2020, shimamu. |
//|                                       https://github.com/shimamu |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, shimamu."
#property link      "https://github.com/shimamu"
#property version   "1.01"
#property strict

#include <stdlib.mqh>

// Parameter.
extern double Lots = 0.04; // 1 Lot = 100,000 currency.

// Global variables.
int MagicNumber = 20201116;
double GridSpace = 0.25;
int Slippage = 3;
int MiliSecondsAfterRequest = 1000;
int MiliSecondsAfterError = 1000;
double BuyMaxPrice = 109.95;
double BuyMinPrice = 100.2;
double SellMaxPrice = 114.95;
double SellMinPrice = 104.2;

struct Order {
    int ticket;  // Order number.
    double lots;
    double price;
};

class Price {
private:
    double value;

public:
    void Price(double price) {
        this.value = price;
    }

    bool isLargerThan(double price) {
        return (price < this.value);
    }

    bool isLessThan(double price) {
        return (this.value < price);
    }

    bool isOrLargerThan(double price) {
        return (price <= this.value);
    }

    bool isOrLessThan(double price) {
        return (this.value <= price);
    }

    double toDouble() {
        return this.value;
    }
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
    virtual double countEntryLots(Price* entryRate) = 0;
    virtual Price* createEntryRate() = 0;
    virtual Price* createExitRate() = 0;
    virtual bool hasEntrySign(Price* entryRate) = 0;
    virtual bool hasExitSign(Price* exitRate) = 0;
    virtual bool isSkipEntry(Price* entryRate) = 0;
    virtual double lastEntryPrice() = 0;
    virtual void setNextTargetAfterEntry() = 0;
    virtual void setNextTargetAfterExit() = 0;

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

    void checkForEntry(Price* entryRate) {
        if (!this.hasEntrySign(entryRate)) {
            if (this.isSkipEntry(entryRate)) {
                this.setNextTargetAfterEntry();
            }
            return;
        }

        double entry_lots = this.countEntryLots(entryRate);
        if (entry_lots <= 0) {
            this.setNextTargetAfterEntry();
            return;
        }

        int ticket = OrderSend(
                         Symbol(),
                         this.OrderType,
                         entry_lots,
                         entryRate.toDouble(),
                         Slippage,
                         0,
                         0,
                         NULL,
                         MagicNumber,
                         0,
                         this.EntryColor);
        if (ticket > 0) {
            this.setNextTargetAfterEntry();
            Sleep(MiliSecondsAfterRequest);
        } else {
            this.checkError("OrderSend");
            Sleep(MiliSecondsAfterError);
        }
    }

    void checkForExit(Price* exitRate) {
        if (!this.hasOrder()) {
            return;
        }

        if (!this.hasExitSign(exitRate)) {
            return;
        }

        bool success = OrderClose(
                           this.last_order.ticket,
                           Lots,
                           exitRate.toDouble(),
                           Slippage,
                           this.ExitColor);
        if (success) {
            this.setNextTargetAfterExit();
            Sleep(MiliSecondsAfterRequest);
        } else {
            this.checkError("OrderClose");
            Sleep(MiliSecondsAfterError);
        }
    }

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

    double countEntryLots(Price* entryRate, double price_a, double price_b) {
        if (!this.entryRateIsBetweenMinAndMaxPrice(entryRate)) {
            return 0;
        }
        int max_grid_num = this.countGrid(price_a, price_b);
        double max_lots = max_grid_num * Lots;
        double need_lots = max_lots - this.lots_total;
        return need_lots;
    }

    int countGrid(double price_a, double price_b) {
        return int(MathAbs(price_a - price_b) / GridSpace) + 1;
    }

    bool entryRateIsBetweenMinAndMaxPrice(Price* entryRate) {
        return (entryRate.isOrLargerThan(this.MinPrice)
                && entryRate.isOrLessThan(this.MaxPrice));
    }

    bool hasLotsForNextEntryPrice(Price* entryRate) {
        return (this.countEntryLots(entryRate) <= -Lots);
    }

    bool hasOneLots() {
        return (this.lots_total == Lots);
    }

    bool hasOrder() {
        if (this.last_order.ticket > 0) {
            return true;
        }
        return false;
    }

    void moveNextTarget(double points) {
        this.next_entry_price += points;
        this.next_exit_price += points;
        this.printNextTarget();
    }

    void moveNextTargetDown() {
        this.moveNextTarget(- GridSpace);
    }

    void moveNextTargetUp() {
        this.moveNextTarget(GridSpace);
    }

    void printNextTarget() {
        printf(
            "-> next %s  entry:%.3f  exit:%.3f",
            this.OrderTypeLabel,
            this.next_entry_price,
            this.next_exit_price);
    }

public:
    void run() {
        Price* entryRate = this.createEntryRate();
        Price* exitRate = this.createExitRate();
        this.checkOrder();
        this.checkForExit(exitRate);
        this.checkForEntry(entryRate);
    }
};

//+------------------------------------------------------------------+
//| Specifics of buy position.                                       |
//+------------------------------------------------------------------+
class BuyOrderRule: public OrderRule {
private:
    bool entryRateIsInAreaForNextEntry(Price* entryRate) {
        return (entryRate.isLargerThan(this.next_entry_price)
                && entryRate.isLessThan(this.lastEntryPrice()));
    }

    bool hasMaxPriceEntryLots(Price* entryRate) {
        return (entryRate.isLargerThan(this.MaxPrice)
                && this.entryRateIsInAreaForNextEntry(entryRate)
                && this.hasOneLots());
    }

    bool hasNextEntryLots(Price* entryRate) {
        return (this.entryRateIsInAreaForNextEntry(entryRate)
                && this.hasLotsForNextEntryPrice(entryRate));
    }

protected:
    virtual double countEntryLots(Price* entryRate) {
        return this.countEntryLots(entryRate, this.MaxPrice, entryRate.toDouble());
    }

    virtual Price* createEntryRate() {
        return new Price(Ask);
    }

    virtual Price* createExitRate() {
        return new Price(Bid);
    }

    virtual bool hasEntrySign(Price* entryRate) {
        return (this.entryRateIsBetweenMinAndMaxPrice(entryRate)
                && entryRate.isOrLessThan(this.next_entry_price));
    }

    virtual bool hasExitSign(Price* exitRate) {
        return exitRate.isOrLargerThan(this.next_exit_price);
    }

    virtual bool isSkipEntry(Price* entryRate) {
        return (hasMaxPriceEntryLots(entryRate)
                || hasNextEntryLots(entryRate));
    }

    virtual double lastEntryPrice() {
        return this.next_entry_price + GridSpace;
    }

    virtual void setNextTargetAfterEntry() {
        this.moveNextTargetDown();
    }

    virtual void setNextTargetAfterExit() {
        this.moveNextTargetUp();
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
        this.printNextTarget();
    }
};

//+------------------------------------------------------------------+
//| Specifics of sell position.                                      |
//+------------------------------------------------------------------+
class SellOrderRule: public OrderRule {
private:
    bool entryRateIsInAreaForNextEntry(Price* entryRate) {
        return (entryRate.isLargerThan(this.lastEntryPrice())
                && entryRate.isLessThan(this.next_entry_price));
    }

    bool hasMinPriceEntryLots(Price* entryRate) {
        return (entryRate.isLessThan(this.MinPrice)
                && this.entryRateIsInAreaForNextEntry(entryRate)
                && this.hasOneLots());
    }

    bool hasNextEntryLots(Price* entryRate) {
        return (this.entryRateIsInAreaForNextEntry(entryRate)
                && this.hasLotsForNextEntryPrice(entryRate));
    }

protected:
    virtual double countEntryLots(Price* entryRate) {
        return this.countEntryLots(entryRate, entryRate.toDouble(), this.MinPrice);
    }

    virtual Price* createEntryRate() {
        return new Price(Bid);
    }

    virtual Price* createExitRate() {
        return new Price(Ask);
    }

    virtual bool hasEntrySign(Price* entryRate) {
        return (this.entryRateIsBetweenMinAndMaxPrice(entryRate)
                && entryRate.isOrLargerThan(this.next_entry_price));
    }

    virtual bool hasExitSign(Price* exitRate) {
        return exitRate.isOrLessThan(this.next_exit_price);
    }

    virtual bool isSkipEntry(Price* entryRate) {
        return (hasMinPriceEntryLots(entryRate)
                || hasNextEntryLots(entryRate));
    }

    virtual double lastEntryPrice() {
        return this.next_entry_price - GridSpace;
    }

    virtual void setNextTargetAfterExit() {
        this.moveNextTargetDown();
    }

    virtual void setNextTargetAfterEntry() {
        this.moveNextTargetUp();
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
        this.printNextTarget();
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
//
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    buy_order_rule.run();
    sell_order_rule.run();
}
//+------------------------------------------------------------------+
