package br.com.tommiranda.getman;

import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;
import javafx.scene.control.cell.TextFieldTableCell;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;

import java.util.stream.Collectors;

public class HeadersComponentController {

    @FXML
    private ToggleButton textModeButton;

    @FXML
    private ToggleButton tableModeButton;

    @FXML
    private ToggleGroup viewModeGroup;

    @FXML
    private TextArea headersTextArea;

    @FXML
    private VBox tableContainer;

    @FXML
    private TableView<HeaderEntry> headersTable;

    @FXML
    private TableColumn<HeaderEntry, String> keyColumn;

    @FXML
    private TableColumn<HeaderEntry, String> valueColumn;

    @FXML
    private HBox tableControls;

    private final ObservableList<HeaderEntry> headerEntries = FXCollections.observableArrayList();
    private boolean isReadOnly = false;

    @FXML
    public void initialize() {
        // Setup Table
        keyColumn.setCellValueFactory(cellData -> cellData.getValue().keyProperty());
        keyColumn.setCellFactory(TextFieldTableCell.forTableColumn());
        keyColumn.setOnEditCommit(event -> {
            if (!isReadOnly) {
                event.getRowValue().setKey(event.getNewValue());
                syncTableToText();
            }
        });

        valueColumn.setCellValueFactory(cellData -> cellData.getValue().valueProperty());
        valueColumn.setCellFactory(TextFieldTableCell.forTableColumn());
        valueColumn.setOnEditCommit(event -> {
            if (!isReadOnly) {
                event.getRowValue().setValue(event.getNewValue());
                syncTableToText();
            }
        });

        headersTable.setItems(headerEntries);

        // Setup View Mode Switching
        viewModeGroup.selectedToggleProperty().addListener((obs, oldVal, newVal) -> {
            if (newVal == textModeButton) {
                headersTextArea.setVisible(true);
                tableContainer.setVisible(false);
                syncTableToText(); // Ensure text is up to date if table was edited
            } else if (newVal == tableModeButton) {
                headersTextArea.setVisible(false);
                tableContainer.setVisible(true);
                syncTextToTable(); // Parse text to table
            }
        });

        // Ensure initial state matches FXML (Table mode selected by default)
        if (tableModeButton.isSelected()) {
            headersTextArea.setVisible(false);
            tableContainer.setVisible(true);
            syncTextToTable();
        } else {
            headersTextArea.setVisible(true);
            tableContainer.setVisible(false);
        }
    }

    public void setReadOnly(boolean readOnly) {
        this.isReadOnly = readOnly;
        headersTextArea.setEditable(!readOnly);
        headersTable.setEditable(!readOnly);
        tableControls.setVisible(!readOnly);
        tableControls.setManaged(!readOnly);
    }

    public String getHeadersText() {
        if (tableModeButton.isSelected()) {
            syncTableToText();
        }
        return headersTextArea.getText();
    }

    public void setHeadersText(String text) {
        headersTextArea.setText(text);
        if (tableModeButton.isSelected()) {
            syncTextToTable();
        }
    }

    @FXML
    private void handleAddHeader() {
        if (!isReadOnly) {
            headerEntries.add(new HeaderEntry("New-Key", "Value"));
            syncTableToText();
        }
    }

    @FXML
    private void handleRemoveHeader() {
        if (!isReadOnly) {
            HeaderEntry selected = headersTable.getSelectionModel().getSelectedItem();
            if (selected != null) {
                headerEntries.remove(selected);
                syncTableToText();
            }
        }
    }

    private void syncTextToTable() {
        headerEntries.clear();
        String text = headersTextArea.getText();
        if (text != null && !text.isEmpty()) {
            String[] lines = text.split("\\n");
            for (String line : lines) {
                String[] parts = line.split(":", 2);
                if (parts.length >= 1) {
                    String key = parts[0].trim();
                    String value = parts.length > 1 ? parts[1].trim() : "";
                    if (!key.isEmpty() || !value.isEmpty()) {
                        headerEntries.add(new HeaderEntry(key, value));
                    }
                }
            }
        }
    }

    private void syncTableToText() {
        String text = headerEntries.stream()
                                   .map(entry -> entry.getKey() + ": " + entry.getValue())
                                   .collect(Collectors.joining("\n"));
        headersTextArea.setText(text);
    }
}
