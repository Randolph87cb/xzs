package com.mindskip.xzs.utility;

import com.mindskip.xzs.domain.exam.ExamPaperQuestionItemObject;
import com.mindskip.xzs.domain.exam.ExamPaperTitleItemObject;
import org.junit.Test;
import java.util.List;
import static org.junit.Assert.assertEquals;

public class ExamPaperFrameUtilTest {
    @Test
    public void expandsLegacyAndCompositeFramesToTheSameFlatContract() {
        String legacy = "[{\"name\":\"旧卷\",\"questionItems\":[{\"id\":1,\"itemOrder\":1},{\"id\":2,\"itemOrder\":2}]}]";
        String composite = "[{\"name\":\"新卷\",\"paperItems\":[{\"type\":\"QUESTION_GROUP\",\"id\":9," +
                "\"itemOrder\":1,\"questionItems\":[{\"id\":1,\"groupItemOrder\":1,\"itemOrder\":1}," +
                "{\"id\":2,\"groupItemOrder\":2,\"itemOrder\":2}]}]}]";
        List<ExamPaperTitleItemObject> oldTitles = JsonUtil.toJsonListObject(legacy, ExamPaperTitleItemObject.class);
        List<ExamPaperTitleItemObject> newTitles = JsonUtil.toJsonListObject(composite, ExamPaperTitleItemObject.class);
        List<ExamPaperQuestionItemObject> oldItems = ExamPaperFrameUtil.expandQuestionItems(oldTitles);
        List<ExamPaperQuestionItemObject> newItems = ExamPaperFrameUtil.expandQuestionItems(newTitles);
        assertEquals(2, oldItems.size());
        assertEquals(oldItems.get(0).getId(), newItems.get(0).getId());
        assertEquals(Integer.valueOf(2), newItems.get(1).getGroupItemOrder());
        assertEquals(oldItems.get(1).getItemOrder(), newItems.get(1).getItemOrder());
    }
}
