package br.com.tommiranda.getman;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public class StateManager {

    private static final String STATE_DIR = "getman-state";
    private static final String OPEN_TABS_DIR = "open-tabs";
    private final ObjectMapper objectMapper = new ObjectMapper();

    public StateManager() {
        createDirectories();
    }

    private void createDirectories() {
        try {
            Path statePath = Paths.get(STATE_DIR);
            if (!Files.exists(statePath)) {
                Files.createDirectory(statePath);
            }
            Path openTabsPath = statePath.resolve(OPEN_TABS_DIR);
            if (!Files.exists(openTabsPath)) {
                Files.createDirectory(openTabsPath);
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public void saveRequestData(RequestData data) {
        if (data.getId() == null || data.getId().isEmpty()) {
            return;
        }
        try {
            System.out.println("SAVING " + data.getId() + " " + data.getMethod());
            Path filePath = Paths.get(STATE_DIR, OPEN_TABS_DIR, data.getId() + ".json");
            objectMapper.writeValue(filePath.toFile(), data);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public void deleteRequestData(String id) {
        if (id == null || id.isEmpty()) {
            return;
        }
        try {
            Path filePath = Paths.get(STATE_DIR, OPEN_TABS_DIR, id + ".json");
            Files.deleteIfExists(filePath);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public List<RequestData> loadAllRequestData() {
        List<RequestData> dataList = new ArrayList<>();
        try (Stream<Path> paths = Files.walk(Paths.get(STATE_DIR, OPEN_TABS_DIR))) {
            List<File> files = paths.filter(Files::isRegularFile)
                    .map(Path::toFile)
                    .toList();

            for (File file : files) {
                try {
                    RequestData data = objectMapper.readValue(file, RequestData.class);
                    dataList.add(data);
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        return dataList;
    }
}
