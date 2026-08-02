package com.mindskip.xzs.utility;

import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.exam.ExamPaperItemObject;
import com.mindskip.xzs.domain.exam.QuestionSelectionUnit;
import org.junit.Test;
import java.util.Arrays;
import java.util.List;
import java.util.Random;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

public class QuestionSelectionUnitSelectorTest {
    @Test
    public void exactSelectionKeepsQuestionGroupAtomic() {
        QuestionSelectionUnit independent = new QuestionSelectionUnit(ExamPaperItemObject.QUESTION, 1, "k", Arrays.asList(question(1)));
        QuestionSelectionUnit group = new QuestionSelectionUnit(ExamPaperItemObject.QUESTION_GROUP, 9, "k",
                Arrays.asList(question(2), question(3), question(4)));
        List<QuestionSelectionUnit> selected = QuestionSelectionUnitSelector.selectExact(Arrays.asList(independent, group), 4, new Random(7));
        assertEquals(2, selected.size());
        assertEquals(4, selected.stream().mapToInt(QuestionSelectionUnit::getQuestionCount).sum());
        assertNull(QuestionSelectionUnitSelector.selectExact(Arrays.asList(group), 2, new Random(7)));
    }

    private Question question(int id) { Question q = new Question(); q.setId(id); return q; }
}
