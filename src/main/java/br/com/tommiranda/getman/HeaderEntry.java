package br.com.tommiranda.getman;

import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;

public class HeaderEntry {
    private final StringProperty key = new SimpleStringProperty("");
    private final StringProperty value = new SimpleStringProperty("");

    public HeaderEntry(String key, String value) {
        this.key.set(key);
        this.value.set(value);
    }

    public String getKey() {
        return key.get();
    }

    public StringProperty keyProperty() {
        return key;
    }

    public void setKey(String key) {
        this.key.set(key);
    }

    public String getValue() {
        return value.get();
    }

    public StringProperty valueProperty() {
        return value;
    }

    public void setValue(String value) {
        this.value.set(value);
    }
}
