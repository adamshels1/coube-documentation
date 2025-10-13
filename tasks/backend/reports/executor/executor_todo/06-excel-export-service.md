# Создать универсальный сервис экспорта в Excel

## Задача
Реализовать универсальный сервис для экспорта отчетов перевозчика в Excel формат с использованием Apache POI.

## Что нужно сделать

### 1. Создать базовый интерфейс экспорта
```java
public interface ExcelExportable<T> {
    String getFileName();
    List<String> getHeaders();
    List<Object> getRowData(T item);
    String getSheetName();
}
```

### 2. Создать универсальный сервис экспорта
```java
@Service
public class ExcelExportService {

    private static final String FONT_NAME = "Arial";
    private static final short HEADER_FONT_SIZE = 12;
    private static final short DATA_FONT_SIZE = 10;
    private static final short HEADER_COLOR_INDEX = IndexedColors.GREY_25_PERCENT.getIndex();
    private static final short BORDER_COLOR = IndexedColors.GREY_40_PERCENT.getIndex();

    public <T> byte[] exportToExcel(List<T> data, ExcelExportable<T> exportable) {
        try (Workbook workbook = new XSSFWorkbook();
             ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {

            Sheet sheet = workbook.createSheet(exportable.getSheetName());

            // Создаем стили
            CellStyle headerStyle = createHeaderStyle(workbook);
            CellStyle dataStyle = createDataStyle(workbook);
            CellStyle currencyStyle = createCurrencyStyle(workbook);
            CellStyle dateStyle = createDateStyle(workbook);

            // Создаем заголовки
            Row headerRow = sheet.createRow(0);
            List<String> headers = exportable.getHeaders();
            for (int i = 0; i < headers.size(); i++) {
                Cell cell = headerRow.createCell(i);
                cell.setCellValue(headers.get(i));
                cell.setCellStyle(headerStyle);
            }

            // Заполняем данные
            int rowNum = 1;
            for (T item : data) {
                Row row = sheet.createRow(rowNum++);
                List<Object> rowData = exportable.getRowData(item);

                for (int i = 0; i < rowData.size(); i++) {
                    Cell cell = row.createCell(i);
                    Object value = rowData.get(i);
                    setCellValue(cell, value, dataStyle, currencyStyle, dateStyle);
                }
            }

            // Автоматически подбираем ширину колонок
            autoSizeColumns(sheet, headers.size());

            workbook.write(outputStream);
            return outputStream.toByteArray();

        } catch (IOException e) {
            throw new ExcelExportException("Failed to export data to Excel", e);
        }
    }

    private void setCellValue(Cell cell, Object value, CellStyle dataStyle,
                             CellStyle currencyStyle, CellStyle dateStyle) {
        if (value == null) {
            cell.setCellValue("");
            cell.setCellStyle(dataStyle);
        } else if (value instanceof String) {
            cell.setCellValue((String) value);
            cell.setCellStyle(dataStyle);
        } else if (value instanceof Number) {
            cell.setCellValue(((Number) value).doubleValue());
            cell.setCellStyle(currencyStyle);
        } else if (value instanceof BigDecimal) {
            cell.setCellValue(((BigDecimal) value).doubleValue());
            cell.setCellStyle(currencyStyle);
        } else if (value instanceof LocalDateTime) {
            cell.setCellValue((LocalDateTime) value);
            cell.setCellStyle(dateStyle);
        } else if (value instanceof LocalDate) {
            cell.setCellValue((LocalDate) value);
            cell.setCellStyle(dateStyle);
        } else {
            cell.setCellValue(value.toString());
            cell.setCellStyle(dataStyle);
        }
    }

    private CellStyle createHeaderStyle(Workbook workbook) {
        CellStyle style = workbook.createCellStyle();
        style.setFillForegroundColor(HEADER_COLOR_INDEX);
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);

        Font font = workbook.createFont();
        font.setFontName(FONT_NAME);
        font.setFontHeightInPoints(HEADER_FONT_SIZE);
        font.setBold(true);
        style.setFont(font);

        style.setBorderTop(BorderStyle.THIN);
        style.setBorderBottom(BorderStyle.THIN);
        style.setBorderLeft(BorderStyle.THIN);
        style.setBorderRight(BorderStyle.THIN);
        style.setTopBorderColor(BORDER_COLOR);
        style.setBottomBorderColor(BORDER_COLOR);
        style.setLeftBorderColor(BORDER_COLOR);
        style.setRightBorderColor(BORDER_COLOR);

        return style;
    }

    private CellStyle createDataStyle(Workbook workbook) {
        CellStyle style = workbook.createCellStyle();

        Font font = workbook.createFont();
        font.setFontName(FONT_NAME);
        font.setFontHeightInPoints(DATA_FONT_SIZE);
        style.setFont(font);

        style.setBorderTop(BorderStyle.THIN);
        style.setBorderBottom(BorderStyle.THIN);
        style.setBorderLeft(BorderStyle.THIN);
        style.setBorderRight(BorderStyle.THIN);
        style.setTopBorderColor(BORDER_COLOR);
        style.setBottomBorderColor(BORDER_COLOR);
        style.setLeftBorderColor(BORDER_COLOR);
        style.setRightBorderColor(BORDER_COLOR);

        return style;
    }

    private CellStyle createCurrencyStyle(Workbook workbook) {
        CellStyle style = createDataStyle(workbook);

        CreationHelper createHelper = workbook.getCreationHelper();
        style.setDataFormat(createHelper.createDataFormat().getFormat("#,##0.00"));

        return style;
    }

    private CellStyle createDateStyle(Workbook workbook) {
        CellStyle style = createDataStyle(workbook);

        CreationHelper createHelper = workbook.getCreationHelper();
        style.setDataFormat(createHelper.createDataFormat().getFormat("dd.mm.yyyy hh:mm"));

        return style;
    }

    private void autoSizeColumns(Sheet sheet, int columnCount) {
        for (int i = 0; i < columnCount; i++) {
            sheet.autoSizeColumn(i);
            // Устанавливаем минимальную и максимальную ширину
            int columnWidth = sheet.getColumnWidth(i);
            if (columnWidth < 2000) {
                sheet.setColumnWidth(i, 2000);
            } else if (columnWidth > 8000) {
                sheet.setColumnWidth(i, 8000);
            }
        }
    }
}
```

### 3. Создать DTO для экспорта АВР и страховых полисов
```java
public class AVRInsuranceExportDTO implements ExcelExportable<AVRInsuranceReportDTO> {

    @Override
    public String getFileName() {
        return "avr-insurance-report-" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd-HH-mm")) + ".xlsx";
    }

    @Override
    public List<String> getHeaders() {
        return Arrays.asList(
            "№ рейса",
            "Заказчик",
            "Сумма (₸)",
            "АВР (ссылка)",
            "Номер полиса",
            "Премия (₸)",
            "Статус",
            "Дата завершения"
        );
    }

    @Override
    public List<Object> getRowData(AVRInsuranceReportDTO item) {
        return Arrays.asList(
            item.getRouteNumber(),
            item.getCustomerName(),
            item.getAmount(),
            item.getAvrDocumentUrl() != null ? "ДА" : "НЕТ",
            item.getInsurancePolicyNumber(),
            item.getBonusAmount(),
            getStatusDisplay(item.getDocumentStatus()),
            item.getCompletedAt()
        );
    }

    @Override
    public String getSheetName() {
        return "АВР и полисы";
    }

    private String getStatusDisplay(String status) {
        switch (status) {
            case "signed": return "Подписан";
            case "pending": return "В ожидании";
            case "rejected": return "Отклонен";
            default: return status;
        }
    }
}
```

### 4. Создать DTO для экспорта утилизации ТС
```java
public class VehicleUtilizationExportDTO implements ExcelExportable<VehicleUtilizationReportDTO> {

    @Override
    public String getFileName() {
        return "vehicle-utilization-" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd-HH-mm")) + ".xlsx";
    }

    @Override
    public List<String> getHeaders() {
        return Arrays.asList(
            "Номер ТС",
            "Модель",
            "Тип кузова",
            "Кол-во рейсов",
            "Перевезено (т)",
            "Грузоподъемность (т)",
            "Коэф. загрузки (%)",
            "Средний вес за рейс (т)",
            "Последний рейс",
            "Статус"
        );
    }

    @Override
    public List<Object> getRowData(VehicleUtilizationReportDTO item) {
        return Arrays.asList(
            item.getVehiclePlate(),
            item.getVehicleModel(),
            item.getVehicleBodyType(),
            item.getTotalRoutes(),
            item.getTotalCargoWeight(),
            item.getVehicleCapacity(),
            item.getUtilizationRate(),
            item.getAverageRouteWeight(),
            item.getLastRouteDate(),
            getStatusDisplay(item.getStatus())
        );
    }

    @Override
    public String getSheetName() {
        return "Утилизация ТС";
    }

    private String getStatusDisplay(String status) {
        switch (status) {
            case "active": return "Активен";
            case "inactive": return "Неактивен";
            case "maintenance": return "На ремонте";
            default: return status;
        }
    }
}
```

### 5. Обновить контроллер для экспорта
```java
@RestController
@RequestMapping("/api/reports/executor")
@ExecutorAccess
public class ExecutorReportsController extends ExecutorReportsBaseController {

    private final ExcelExportService excelExportService;
    private final AVRInsuranceExportDTO avrInsuranceExport;
    private final VehicleUtilizationExportDTO vehicleUtilizationExport;

    @GetMapping("/avr-insurance/export")
    public ResponseEntity<Resource> exportAVRInsuranceReport(
        @RequestParam(required = false) String routeNumber,
        @RequestParam(required = false) Long customerId,
        @RequestParam(required = false) String documentStatus,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateFrom,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateTo,
        HttpServletResponse response
    ) {
        Long executorId = getCurrentExecutorId();
        AVRInsuranceFilterDTO filter = new AVRInsuranceFilterDTO(routeNumber, customerId, documentStatus, dateFrom, dateTo);

        // Получаем все данные без пагинации для экспорта
        List<AVRInsuranceReportDTO> data = avrInsuranceService.getAllAVRInsuranceData(executorId, filter);

        byte[] excelData = excelExportService.exportToExcel(data, avrInsuranceExport);

        ByteArrayResource resource = new ByteArrayResource(excelData);

        return ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=" + avrInsuranceExport.getFileName())
            .contentType(MediaType.parseMediaType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
            .body(resource);
    }

    @GetMapping("/vehicle-utilization/export")
    public ResponseEntity<Resource> exportVehicleUtilizationReport(
        @RequestParam(required = false) Long vehicleId,
        @RequestParam(required = false) String vehiclePlate,
        @RequestParam(required = false) String bodyType,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateFrom,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateTo
    ) {
        Long executorId = getCurrentExecutorId();
        VehicleUtilizationFilterDTO filter = new VehicleUtilizationFilterDTO(vehicleId, vehiclePlate, bodyType, dateFrom, dateTo);

        List<VehicleUtilizationReportDTO> data = vehicleUtilizationService.getAllVehicleUtilizationData(executorId, filter);

        byte[] excelData = excelExportService.exportToExcel(data, vehicleUtilizationExport);

        ByteArrayResource resource = new ByteArrayResource(excelData);

        return ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=" + vehicleUtilizationExport.getFileName())
            .contentType(MediaType.parseMediaType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
            .body(resource);
    }
}
```

### 6. Создать кастомное исключение
```java
public class ExcelExportException extends RuntimeException {
    public ExcelExportException(String message) {
        super(message);
    }

    public ExcelExportException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

### 7. Добавить обработку ошибок экспорта
```java
@ControllerAdvice
public class ExcelExportExceptionHandler {

    @ExceptionHandler(ExcelExportException.class)
    public ResponseEntity<Map<String, Object>> handleExcelExportException(ExcelExportException e) {
        Map<String, Object> body = new HashMap<>();
        body.put("timestamp", LocalDateTime.now());
        body.put("status", HttpStatus.INTERNAL_SERVER_ERROR.value());
        body.put("error", "Export Error");
        body.put("message", "Failed to export data: " + e.getMessage());

        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(body);
    }

    @ExceptionHandler(MaxSizeExceededException.class)
    public ResponseEntity<Map<String, Object>> handleMaxSizeException(MaxSizeExceededException e) {
        Map<String, Object> body = new HashMap<>();
        body.put("timestamp", LocalDateTime.now());
        body.put("status", HttpStatus.BAD_REQUEST.value());
        body.put("error", "File Too Large");
        body.put("message", "Export data is too large. Please apply filters to reduce the data size.");

        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(body);
    }
}
```

### 8. Создать тест для экспорта
```java
@SpringBootTest
class ExcelExportServiceTest {

    @Autowired
    private ExcelExportService excelExportService;

    @Test
    void shouldExportAVRInsuranceDataToExcel() {
        // Given
        List<AVRInsuranceReportDTO> data = createMockAVRInsuranceData();
        AVRInsuranceExportDTO exportable = new AVRInsuranceExportDTO();

        // When
        byte[] result = excelExportService.exportToExcel(data, exportable);

        // Then
        assertNotNull(result);
        assertTrue(result.length > 0);

        // Verify Excel file structure
        try (Workbook workbook = new XSSFWorkbook(new ByteArrayInputStream(result))) {
            assertEquals(1, workbook.getNumberOfSheets());
            Sheet sheet = workbook.getSheetAt(0);
            assertTrue(sheet.getPhysicalNumberOfRows() > 1); // Header + data
        } catch (IOException e) {
            fail("Failed to read generated Excel file", e);
        }
    }

    @Test
    void shouldHandleEmptyData() {
        // Given
        List<AVRInsuranceReportDTO> emptyData = Collections.emptyList();
        AVRInsuranceExportDTO exportable = new AVRInsuranceExportDTO();

        // When
        byte[] result = excelExportService.exportToExcel(emptyData, exportable);

        // Then
        assertNotNull(result);
        assertTrue(result.length > 0);

        try (Workbook workbook = new XSSFWorkbook(new ByteArrayInputStream(result))) {
            Sheet sheet = workbook.getSheetAt(0);
            assertEquals(1, sheet.getPhysicalNumberOfRows()); // Only header
        } catch (IOException e) {
            fail("Failed to read generated Excel file", e);
        }
    }
}
```

## Требования
- ✅ Универсальный сервис для любого типа данных
- ✅ Красивое форматирование Excel (стили, границы, цвета)
- ✅ Поддержка разных типов данных (числа, даты, строки)
- ✅ Автоматическая подборка ширины колонок
- ✅ Обработка ошибок экспорта
- ✅ Лимит размера файла (максимум 10МБ)

## Критерии приемки
- [ ] Excel файлы генерируются корректно
- [ ] Форматирование ячеек работает (валюта, даты)
- [ ] Заголовки и данные отображаются правильно
- [ ] Ширина колонок автоматическая
- [ ] Обработка больших объемов данных
- [ ] Все тесты проходят
- [ ] Файлы открываются в MS Excel и LibreOffice