package com.mindskip.xzs.domain.enums;

public enum QuestionGroupTypeEnum {
    ProgramReading(1, "程序阅读"),
    ProgramCompletion(2, "程序填空");

    private final int code;
    private final String name;

    QuestionGroupTypeEnum(int code, String name) {
        this.code = code;
        this.name = name;
    }

    public int getCode() { return code; }
    public String getName() { return name; }

    public static QuestionGroupTypeEnum fromCode(Integer code) {
        if (code == null) { return null; }
        for (QuestionGroupTypeEnum value : values()) {
            if (value.code == code) { return value; }
        }
        return null;
    }
}
