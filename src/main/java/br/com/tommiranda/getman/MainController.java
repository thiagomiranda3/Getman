package br.com.tommiranda.getman;

import javafx.event.Event;
import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.control.Tab;
import javafx.scene.control.TabPane;
import javafx.scene.layout.BorderPane;

import java.io.IOException;

public class MainController {

    @FXML
    private TabPane mainTabPane;

    @FXML
    public void initialize() {
        createAndSelectNewTab();
    }

    @FXML
    public void onPlusTabSelected(Event event) {
        Tab tab = (Tab) event.getSource();
        if (tab.isSelected()) {
            createAndSelectNewTab();
        }
    }

    private void createAndSelectNewTab() {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/request_tab.fxml"));
            BorderPane requestView = loader.load();
            
            Tab tab = new Tab("New Request");
            tab.setContent(requestView);
            
            // Add before the last tab (which is the + tab)
            int index = mainTabPane.getTabs().size() - 1;
            // Safety check, though + tab should always be there
            if (index < 0) index = 0;
            
            mainTabPane.getTabs().add(index, tab);
            mainTabPane.getSelectionModel().select(tab);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
