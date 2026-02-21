package br.com.tommiranda.getman;

import javafx.application.Platform;
import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.control.Button;
import javafx.scene.control.Tab;
import javafx.scene.control.TabPane;
import javafx.scene.layout.BorderPane;

import java.io.IOException;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

public class MainController {

    @FXML
    private TabPane mainTabPane;

    @FXML
    private Button plusButton;

    private final StateManager stateManager = new StateManager();

    @FXML
    public void initialize() {
        mainTabPane.getSelectionModel().selectedItemProperty().addListener((_, oldTab, _) -> {
            if (oldTab != null && oldTab.getUserData() instanceof RequestTabController) {
                ((RequestTabController) oldTab.getUserData()).saveState();
            }
        });

        List<RequestData> savedRequests = stateManager.loadAllRequestData();
        if (savedRequests.isEmpty()) {
            createAndSelectNewTab(null);
        } else {
            for (RequestData data : savedRequests) {
                createAndSelectNewTab(data);
            }
            // Select the first tab if available
            if (!mainTabPane.getTabs().isEmpty()) {
                mainTabPane.getSelectionModel().select(0);
            }
        }
    }

    @FXML
    public void onPlusButtonClicked() {
        plusButton.setDisable(true);
        createAndSelectNewTab(null);
        plusButton.setDisable(false);
    }

    private void createAndSelectNewTab(RequestData data) {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/request_tab.fxml"));
            BorderPane requestView = loader.load();
            RequestTabController controller = loader.getController();

            String tabId;
            if (data != null) {
                tabId = data.getId();
            } else {
                tabId = UUID.randomUUID().toString();
            }

            controller.setTabId(tabId);
            controller.setStateManager(stateManager);

            if (data != null) {
                controller.loadState(data);
            } else {
                // Save initial state for new tab
                controller.saveState();
            }

            Tab tab = new Tab("Request");
            tab.setContent(requestView);
            tab.setUserData(controller);
            tab.setOnClosed(e -> stateManager.deleteRequestData(tabId));

            // Add before the last tab (which is the + tab)
            int index = mainTabPane.getTabs().size() - 1;
            // Safety check, though + tab should always be there
            if (index < 0) {
                index = 0;
            }

            mainTabPane.getTabs().add(index, tab);
            mainTabPane.getSelectionModel().select(tab);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
